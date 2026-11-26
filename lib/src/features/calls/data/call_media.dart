import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'call_media.g.dart';

/// Camera, microphone and the peer-to-peer connection for one call.
///
/// Audio and video go directly between the two devices, encrypted end to end
/// by WebRTC (DTLS-SRTP), or through the TURN relay when no direct path
/// exists. The server only relays the session descriptions passed to
/// `onSignal` / [handleSignal].
abstract interface class CallMedia {
  /// Opens the microphone (and the camera when [video]).
  /// Throws [CallMediaException] if access is denied.
  Future<void> start({required bool video});

  /// Creates the connection. The caller ([initiator]) sends the offer; the
  /// other side answers it in [handleSignal].
  Future<void> connect({
    required List<Map<String, dynamic>> iceServers,
    required bool initiator,
    required void Function(Map<String, dynamic> data) onSignal,
    required void Function(MediaConnection state) onConnection,
  });

  /// Session data from the other side (offer, answer or ICE candidate).
  Future<void> handleSignal(Map<String, dynamic> data);

  /// Turns our camera on or off mid-call (no renegotiation needed).
  Future<void> setVideo(bool on);

  void setMuted(bool muted);

  /// Loudspeaker vs earpiece (phones only).
  Future<void> setSpeaker(bool on);

  Future<void> switchCamera();

  bool get canSwitchCamera;
  bool get hasSpeakerToggle;

  Widget localView();

  /// The other side's video. [fill] crops it to fill the area (a portrait
  /// phone screen); otherwise the whole picture is shown (a wide window, where
  /// filling would crop a portrait phone camera to a close-up).
  Widget remoteView({required bool fill});

  /// What the connection is actually delivering right now (from WebRTC's own
  /// statistics), or null before the call connects.
  Future<CallQuality?> quality();

  Future<void> close();
}

enum MediaConnection { connecting, connected, interrupted, failed }

/// A snapshot of the call's media, for the call screen's quality line.
class CallQuality {
  const CallQuality({
    this.receivedWidth,
    this.receivedHeight,
    this.receivedFps,
    this.sentWidth,
    this.sentHeight,
    this.limitedBy,
    this.relayed,
  });

  /// The other side's video as it arrives here.
  final int? receivedWidth, receivedHeight;
  final double? receivedFps;

  /// Our video as we send it.
  final int? sentWidth, sentHeight;

  /// Why WebRTC is sending below the camera's resolution: 'bandwidth' or
  /// 'cpu' (null when it isn't limited).
  final String? limitedBy;

  /// True when media goes through the TURN relay rather than directly.
  final bool? relayed;
}

class CallMediaException implements Exception {
  const CallMediaException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WebRtcCallMedia implements CallMedia {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  MediaStream? _audioStream;
  MediaStream? _videoStream;
  RTCPeerConnection? _pc;
  RTCRtpTransceiver? _videoTransceiver;
  void Function(Map<String, dynamic>)? _onSignal;
  final _pendingCandidates = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;
  final _ready = Completer<void>();
  bool _closed = false;
  bool _initiator = false;
  bool _audioAdded = false;
  Future<void> _signals = Future.value();

  MediaStreamTrack? get _videoTrack =>
      _videoStream?.getVideoTracks().firstOrNull;

  Future<void> _initRenderers() async {
    if (_renderersReady) return;
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _renderersReady = true;
  }

  @override
  Future<void> start({required bool video}) async {
    await _initRenderers();
    try {
      _audioStream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
    } catch (e) {
      developer.log('Microphone unavailable',
          name: 'medivitallink.call', error: e);
      throw const CallMediaException('Allow microphone access to make calls.');
    }
    if (video) await setVideo(true);
  }

  @override
  Future<void> connect({
    required List<Map<String, dynamic>> iceServers,
    required bool initiator,
    required void Function(Map<String, dynamic> data) onSignal,
    required void Function(MediaConnection state) onConnection,
  }) async {
    _onSignal = onSignal;
    _initiator = initiator;
    final pc = _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      onSignal({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex
      });
    };
    pc.onTrack = (event) {
      if (event.track.kind != 'video') return; // remote audio plays by itself
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
      } else {
        developer.log('Remote video arrived without a stream',
            name: 'medivitallink.call');
      }
    };
    pc.onConnectionState = (state) => onConnection(switch (state) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
            MediaConnection.connected,
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
            MediaConnection.interrupted,
          RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
            MediaConnection.failed,
          _ => MediaConnection.connecting,
        });

    if (initiator) {
      await _addAudio();
      await _addOwnVideoSlot();
      await _sendOffer();
    }
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Our microphone, attached to our stream (once per call).
  Future<void> _addAudio() async {
    final stream = _audioStream;
    if (stream == null || _audioAdded) return;
    _audioAdded = true;
    for (final track in stream.getAudioTracks()) {
      await _pc!.addTrack(track, stream);
    }
  }

  /// Each side sends video on its own send-only slot, attached to the same
  /// stream as its audio. The other side then receives the video *with* that
  /// stream, which is what the native video renderers need. The camera is
  /// switched on and off later by swapping the slot's track (no renegotiation).
  Future<void> _addOwnVideoSlot() async {
    final stream = _audioStream;
    _videoTransceiver = await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.SendOnly,
        streams: [if (stream != null) stream],
      ),
    );
    await _videoTransceiver!.sender.replaceTrack(_videoTrack);
  }

  Future<void> _sendOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _onSignal?.call({'sdp': offer.sdp, 'sdpType': 'offer'});
  }

  /// Signals are handled strictly one at a time, in arrival order: an answer
  /// must be applied before the next offer, candidates after descriptions.
  @override
  Future<void> handleSignal(Map<String, dynamic> data) {
    return _signals =
        _signals.then((_) => _handle(data)).catchError((Object e) {
      developer.log('Failed to apply call signal',
          name: 'medivitallink.call', error: e);
    });
  }

  Future<void> _handle(Map<String, dynamic> data) async {
    await _ready.future; // an offer can arrive while we're still setting up
    final pc = _pc;
    if (pc == null || _closed) return;

    final sdp = data['sdp'] as String?;
    if (sdp != null) {
      final type = data['sdpType'] as String;
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescriptionSet = true;
      if (type == 'offer') {
        final firstOffer = !_audioAdded;
        // Answering side: attach our microphone to the audio slot the offer
        // created (adding it earlier would create an unpaired extra slot).
        await _addAudio();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _onSignal?.call({'sdp': answer.sdp, 'sdpType': 'answer'});
        if (firstOffer && !_initiator) {
          // Now that the call is set up, offer our own video slot back.
          // Only the answering side does this, once, so offers never collide.
          await _addOwnVideoSlot();
          await _sendOffer();
        }
      }
      for (final c in _pendingCandidates) {
        await pc.addCandidate(c);
      }
      _pendingCandidates.clear();
      return;
    }

    final candidate = data['candidate'] as String?;
    if (candidate != null) {
      final ice = RTCIceCandidate(
        candidate,
        data['sdpMid'] as String?,
        (data['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_remoteDescriptionSet) {
        await pc.addCandidate(ice);
      } else {
        _pendingCandidates.add(ice);
      }
    }
  }

  @override
  Future<void> setVideo(bool on) async {
    await _initRenderers();
    if (on) {
      if (_videoStream != null) return;
      try {
        _videoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': 'user'},
        });
      } catch (e) {
        developer.log('Camera unavailable',
            name: 'medivitallink.call', error: e);
        throw const CallMediaException('Allow camera access to turn on video.');
      }
      _localRenderer.srcObject = _videoStream;
      await _videoTransceiver?.sender.replaceTrack(_videoTrack);
    } else {
      await _videoTransceiver?.sender.replaceTrack(null);
      _localRenderer.srcObject = null;
      await _stopStream(_videoStream);
      _videoStream = null;
    }
  }

  @override
  void setMuted(bool muted) {
    for (final track
        in _audioStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  static bool get _isPhone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  bool get hasSpeakerToggle => _isPhone;

  @override
  bool get canSwitchCamera => _isPhone;

  @override
  Future<void> setSpeaker(bool on) async {
    if (_isPhone) await Helper.setSpeakerphoneOn(on);
  }

  @override
  Future<void> switchCamera() async {
    final track = _videoTrack;
    if (track != null && _isPhone) await Helper.switchCamera(track);
  }

  @override
  Widget localView() => RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );

  @override
  Widget remoteView({required bool fill}) => RTCVideoView(
        _remoteRenderer,
        objectFit: fill
            ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
            : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );

  @override
  Future<CallQuality?> quality() async {
    final pc = _pc;
    if (pc == null || _closed) return null;
    final reports = await pc.getStats();
    final byId = {for (final r in reports) r.id: r};
    int? asInt(Object? v) => v is num ? v.toInt() : null;

    int? inW, inH, outW, outH;
    double? inFps;
    String? limitedBy;
    bool? relayed;
    for (final r in reports) {
      final v = r.values;
      final video = v['kind'] == 'video' || v['mediaType'] == 'video';
      if (r.type == 'inbound-rtp' && video) {
        inW = asInt(v['frameWidth']) ?? inW;
        inH = asInt(v['frameHeight']) ?? inH;
        final fps = v['framesPerSecond'];
        if (fps is num) inFps = fps.toDouble();
      } else if (r.type == 'outbound-rtp' && video) {
        outW = asInt(v['frameWidth']) ?? outW;
        outH = asInt(v['frameHeight']) ?? outH;
        final reason = v['qualityLimitationReason'];
        if (reason is String && reason != 'none') limitedBy = reason;
      } else if (r.type == 'candidate-pair' &&
          v['state'] == 'succeeded' &&
          (v['nominated'] == true || v['selected'] == true)) {
        final local = byId[v['localCandidateId']]?.values['candidateType'];
        final remote = byId[v['remoteCandidateId']]?.values['candidateType'];
        relayed = local == 'relay' || remote == 'relay';
      }
    }
    return CallQuality(
      receivedWidth: inW,
      receivedHeight: inH,
      receivedFps: inFps,
      sentWidth: outW,
      sentHeight: outH,
      limitedBy: limitedBy,
      relayed: relayed,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.complete();
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    await _stopStream(_audioStream);
    await _stopStream(_videoStream);
    _audioStream = _videoStream = null;
    if (_renderersReady) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
    }
  }

  static Future<void> _stopStream(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }
}

/// Creates the media for one call. Tests override this with a fake.
@riverpod
CallMedia Function() callMediaFactory(Ref ref) => WebRtcCallMedia.new;
