import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../../vitals_monitor/data/repositories/vitals_repository.dart';
import '../../data/call_media.dart';
import '../../data/models/call_models.dart';
import '../../data/repositories/call_signaling.dart';

part 'call_controller.g.dart';

/// The call this device is on or ringing with, if any.
///
/// outgoing/incoming -> connecting -> active -> ended. The caller sends the
/// WebRTC offer once answered. An ended care-team call stays on screen until
/// the clinician records the case outcome; other ended calls close themselves.
@Riverpod(keepAlive: true)
class CallController extends _$CallController {
  CallSignaling? _signaling;
  CallMedia? _media;
  Timer? _ringer;
  Timer? _autoDismiss;

  static const _dismissAfter = Duration(milliseconds: 2500);

  @override
  CallState? build() {
    final signaling = _signaling = ref.watch(callSignalingProvider);
    if (signaling != null) {
      final sub = signaling.connect().listen(_onMessage);
      ref.onDispose(sub.cancel);
    }
    ref.onDispose(() {
      _ringer?.cancel();
      _autoDismiss?.cancel();
      _closeMedia();
    });
    return null;
  }

  UserModel? get _me => ref.read(currentUserProvider);
  bool get _simulated => _signaling?.simulated ?? false;
  bool get _busy => state?.isLive ?? false;

  /// Care team: ring a patient, about their case when [escalationId] is given.
  Future<void> callPatient({
    required String patientId,
    required String patientName,
    String? escalationId,
  }) =>
      _place(
        to: patientId,
        peer:
            CallPeer(id: patientId, role: UserRole.patient, name: patientName),
        patientId: patientId,
        escalationId: escalationId,
      );

  Future<void> _place({
    required String to,
    required CallPeer peer,
    required String patientId,
    String? escalationId,
  }) async {
    if (_busy || _signaling == null) return;
    _autoDismiss?.cancel();
    final callId = const Uuid().v4();
    state = CallState(
      callId: callId,
      phase: CallPhase.outgoing,
      peer: peer,
      patientId: patientId,
      escalationId: escalationId,
      simulated: _simulated,
    );
    if (!await _openMedia(callId)) return;
    final sent = _signaling!.send({
      'type': 'invite',
      'callId': callId,
      'to': to,
      if (escalationId != null) 'escalationId': escalationId,
      'video': false,
    });
    if (!sent) {
      _end(callId, CallEndReason.failed,
          message: 'Not connected. Check your internet.');
    }
  }

  Future<void> accept() async {
    final call = state;
    if (call == null || call.phase != CallPhase.incoming) return;
    _stopRinging();
    state = call.copyWith(phase: CallPhase.connecting);
    if (!await _openMedia(call.callId)) {
      _signaling?.send({'type': 'decline', 'callId': call.callId});
      return;
    }
    if (!(_signaling?.send({'type': 'accept', 'callId': call.callId}) ??
        false)) {
      _end(call.callId, CallEndReason.failed,
          message: 'Not connected. Check your internet.');
    }
  }

  void decline() {
    final call = state;
    if (call == null || call.phase != CallPhase.incoming) return;
    _signaling?.send({'type': 'decline', 'callId': call.callId});
    _end(call.callId, CallEndReason.declined);
  }

  void hangUp() {
    final call = state;
    if (call == null || !call.isLive) return;
    _signaling?.send({'type': 'hangup', 'callId': call.callId});
    final reason = call.connectedAt == null && call.phase == CallPhase.outgoing
        ? CallEndReason.cancelled
        : CallEndReason.hungUp;
    _end(call.callId, reason);
  }

  /// Closes the ended-call screen.
  void dismiss() {
    if (state?.isLive ?? false) return;
    _autoDismiss?.cancel();
    state = null;
  }

  void toggleMute() {
    final call = state;
    if (call == null || !call.isLive) return;
    _media?.setMuted(!call.muted);
    state = call.copyWith(muted: !call.muted);
  }

  /// Audio → video and back. The other side is told, so its screen switches.
  Future<void> toggleVideo() async {
    final call = state;
    if (call == null || !call.isLive) return;
    final on = !call.localVideo;
    // Demo mode has no connection, but still shows your own camera.
    if (on && _media == null && _simulated) {
      _media = ref.read(callMediaFactoryProvider)();
    }
    try {
      await _media?.setVideo(on);
    } on CallMediaException catch (e) {
      state = state?.copyWith(errorMessage: e.message);
      return;
    }
    if (state?.callId != call.callId) return;
    state = state!.copyWith(localVideo: on, speakerOn: on ? true : null);
    if (on) {
      unawaited(
          _media?.setSpeaker(true)); // video calls are held away from the ear
    }
    _signaling?.send({'type': 'media', 'callId': call.callId, 'video': on});
  }

  Future<void> toggleSpeaker() async {
    final call = state;
    if (call == null || !call.isLive) return;
    await _media?.setSpeaker(!call.speakerOn);
    state = state?.copyWith(speakerOn: !call.speakerOn);
  }

  Future<void> switchCamera() async => _media?.switchCamera();

  /// The media for the current call, for the call screen's video views.
  CallMedia? get media => _media;

  void _onMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    final callId = msg['callId'] as String?;
    final call = state;
    final isCurrent = call != null && call.callId == callId;

    switch (type) {
      case 'incoming':
        _incoming(msg);
      case 'ringing' when isCurrent:
        final escalationId = msg['escalationId'] as String?;
        if (escalationId != null) {
          state = call.copyWith(escalationId: escalationId);
        }
      case 'accepted' when isCurrent:
        _accepted(call, msg);
      case 'busy' when isCurrent:
        _end(call.callId, CallEndReason.busy);
      case 'ended' when isCurrent:
        _end(call.callId, CallEndReason.fromServer(msg['reason'] as String?));
      case 'signal' when isCurrent:
        final data = msg['data'];
        if (data is Map<String, dynamic>) unawaited(_media?.handleSignal(data));
      case 'media' when isCurrent:
        state = call.copyWith(remoteVideo: msg['video'] == true);
      case 'error' when isCurrent && call.isLive:
        _end(call.callId, CallEndReason.failed,
            message: msg['message'] as String?);
      case 'error':
        developer.log('Call signalling error: ${msg['message']}',
            name: 'medivitallink.call');
    }
  }

  void _incoming(Map<String, dynamic> msg) {
    if (_busy) return; // the server already tells the caller we're on a call
    _autoDismiss?.cancel();
    final from = msg['from'] as Map<String, dynamic>? ?? const {};
    final role =
        UserRole.values.where((r) => r.name == from['role']).firstOrNull ??
            UserRole.nurse;
    final patientId = msg['patientId'] as String;
    state = CallState(
      callId: msg['callId'] as String,
      phase: CallPhase.incoming,
      peer: CallPeer(
        id: from['id'] as String?,
        role: role,
        name: role == UserRole.patient
            ? _patientName(patientId)
            : roleLabel(role),
      ),
      patientId: patientId,
      escalationId: msg['escalationId'] as String?,
      simulated: _simulated,
    );
    _startRinging();
  }

  Future<void> _accepted(CallState call, Map<String, dynamic> msg) async {
    final by = msg['by'] as Map<String, dynamic>? ?? const {};
    final iAnswered = by['id'] == _me?.id;
    var next = call.copyWith(
      phase: CallPhase.connecting,
      escalationId: msg['escalationId'] as String?,
      peer: iAnswered ? null : call.peer.copyWith(id: by['id'] as String?),
    );
    if (_simulated) {
      // Nothing to connect: the other side is simulated.
      next =
          next.copyWith(phase: CallPhase.active, connectedAt: DateTime.now());
      state = next;
      return;
    }
    state = next;
    final media = _media;
    final signaling = _signaling;
    if (media == null || signaling == null) return;
    var iceServers = const <Map<String, dynamic>>[];
    try {
      iceServers = await signaling.iceServers();
    } catch (e) {
      developer.log('No ICE servers; trying a direct connection',
          name: 'medivitallink.call', error: e);
    }
    if (state?.callId != call.callId) return;
    await media.connect(
      iceServers: iceServers,
      initiator: !iAnswered, // the caller makes the offer
      onSignal: (data) => signaling
          .send({'type': 'signal', 'callId': call.callId, 'data': data}),
      onConnection: (connection) => _onConnection(call.callId, connection),
    );
  }

  void _onConnection(String callId, MediaConnection connection) {
    final call = state;
    if (call == null || call.callId != callId || !call.isLive) return;
    switch (connection) {
      case MediaConnection.connected:
        state = call.copyWith(
            phase: CallPhase.active,
            connectedAt: call.connectedAt ?? DateTime.now());
      case MediaConnection.failed:
        _signaling?.send({'type': 'hangup', 'callId': callId});
        _end(callId, CallEndReason.failed, message: 'The connection was lost.');
      case MediaConnection.interrupted || MediaConnection.connecting:
        break;
    }
  }

  Future<bool> _openMedia(String callId) async {
    if (_simulated) return true; // mock backend: no microphone needed
    await _closeMedia();
    final media = _media = ref.read(callMediaFactoryProvider)();
    try {
      await media.start(video: false);
      return true;
    } on CallMediaException catch (e) {
      _end(callId, CallEndReason.failed, message: e.message);
      return false;
    }
  }

  Future<void> _closeMedia() async {
    final media = _media;
    _media = null;
    await media?.close();
  }

  void _end(String callId, CallEndReason reason, {String? message}) {
    final call = state;
    if (call == null || call.callId != callId || !call.isLive) return;
    _stopRinging();
    unawaited(_closeMedia());
    state = call.copyWith(
      phase: CallPhase.ended,
      endedAt: DateTime.now(),
      endReason: reason,
      errorMessage: message,
      localVideo: false,
      remoteVideo: false,
    );
    // The care team records what happens next with the case; others are done.
    final recordsOutcome =
        (_me?.role ?? UserRole.patient) != UserRole.patient &&
            call.escalationId != null &&
            call.connectedAt != null;
    if (!recordsOutcome) {
      _autoDismiss?.cancel();
      _autoDismiss = Timer(_dismissAfter, () {
        if (state?.callId == callId && !(state?.isLive ?? true)) state = null;
      });
    }
  }

  void _startRinging() {
    _ringer?.cancel();
    void ring() {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }

    ring();
    _ringer = Timer.periodic(const Duration(seconds: 2), (_) => ring());
  }

  void _stopRinging() {
    _ringer?.cancel();
    _ringer = null;
  }

  String _patientName(String patientId) {
    final patients =
        ref.read(monitoredPatientsProvider).valueOrNull ?? const [];
    for (final p in patients) {
      if (p.id == patientId) return p.name;
    }
    return 'Patient';
  }
}
