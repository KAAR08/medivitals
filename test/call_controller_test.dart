import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medivitallink/src/data/services/mock_data.dart';
import 'package:medivitallink/src/features/auth/data/models/user_model.dart';
import 'package:medivitallink/src/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:medivitallink/src/features/calls/data/call_media.dart';
import 'package:medivitallink/src/features/calls/data/models/call_models.dart';
import 'package:medivitallink/src/features/calls/data/repositories/call_signaling.dart';
import 'package:medivitallink/src/features/calls/presentation/viewmodels/call_controller.dart';

/// Records what the app sends; the test plays the server.
class FakeSignaling implements CallSignaling {
  final sent = <Map<String, dynamic>>[];
  final _server = StreamController<Map<String, dynamic>>.broadcast();
  bool connected = true;

  void receive(Map<String, dynamic> message) => _server.add(message);
  Map<String, dynamic> lastOfType(String type) =>
      sent.lastWhere((m) => m['type'] == type);

  @override
  Stream<Map<String, dynamic>> connect() => _server.stream;

  @override
  bool send(Map<String, dynamic> message) {
    if (!connected) return false;
    sent.add(message);
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() async => [
        {
          'urls': ['turn:relay.test:3478'],
          'username': 'u',
          'credential': 'c'
        },
      ];

  @override
  bool get simulated => false;
}

class FakeMedia implements CallMedia {
  bool started = false;
  bool closed = false;
  bool? initiator;
  bool muted = false;
  bool video = false;
  bool failStart = false;
  List<Map<String, dynamic>>? iceServers;
  final handled = <Map<String, dynamic>>[];
  late void Function(Map<String, dynamic>) onSignal;
  late void Function(MediaConnection) onConnection;

  @override
  Future<void> start({required bool video}) async {
    if (failStart) {
      throw const CallMediaException('Allow microphone access to make calls.');
    }
    started = true;
  }

  @override
  Future<void> connect({
    required List<Map<String, dynamic>> iceServers,
    required bool initiator,
    required void Function(Map<String, dynamic> data) onSignal,
    required void Function(MediaConnection state) onConnection,
  }) async {
    this.iceServers = iceServers;
    this.initiator = initiator;
    this.onSignal = onSignal;
    this.onConnection = onConnection;
  }

  @override
  Future<void> handleSignal(Map<String, dynamic> data) async =>
      handled.add(data);

  @override
  Future<void> setVideo(bool on) async => video = on;

  @override
  void setMuted(bool muted) => this.muted = muted;

  @override
  Future<void> setSpeaker(bool on) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  bool get canSwitchCamera => false;

  @override
  bool get hasSpeakerToggle => false;

  @override
  Widget localView() => const SizedBox();

  @override
  Widget remoteView() => const SizedBox();

  @override
  Future<void> close() async => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // ringing uses haptics
  late FakeSignaling signaling;
  late FakeMedia media;

  ProviderContainer containerFor(UserModel user) {
    signaling = FakeSignaling();
    media = FakeMedia();
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => user),
      callSignalingProvider.overrideWith((ref) => signaling),
      callMediaFactoryProvider.overrideWith((ref) => () => media),
    ]);
    addTearDown(container.dispose);
    container.listen(callControllerProvider, (_, __) {}); // keep it built
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('nurse calls a patient: the caller makes the offer once answered',
      () async {
    final container = containerFor(mockNurse);
    final calls = container.read(callControllerProvider.notifier);

    await calls.callPatient(
        patientId: kJohnId, patientName: 'John Doe', escalationId: 'esc-1');
    final invite = signaling.lastOfType('invite');
    expect(invite, containsPair('to', kJohnId));
    expect(invite, containsPair('escalationId', 'esc-1'));
    expect(invite['video'], isFalse, reason: 'calls start as audio');
    expect(media.started, isTrue);
    final callId = invite['callId'] as String;
    expect(container.read(callControllerProvider)!.phase, CallPhase.outgoing);

    signaling.receive({
      'type': 'accepted',
      'callId': callId,
      'escalationId': 'esc-1',
      'by': {'id': kJohnId, 'role': 'patient'},
    });
    await settle();
    await settle();
    expect(media.initiator, isTrue);
    expect(media.iceServers, isNotEmpty,
        reason: 'TURN servers come from the engine');
    expect(container.read(callControllerProvider)!.phase, CallPhase.connecting);

    // Our session data goes out; theirs comes in.
    media.onSignal({'sdp': 'offer-sdp', 'sdpType': 'offer'});
    expect(signaling.lastOfType('signal')['data'],
        {'sdp': 'offer-sdp', 'sdpType': 'offer'});
    signaling.receive({
      'type': 'signal',
      'callId': callId,
      'data': {'sdp': 'answer', 'sdpType': 'answer'}
    });
    await settle();
    expect(media.handled.single['sdp'], 'answer');

    media.onConnection(MediaConnection.connected);
    final active = container.read(callControllerProvider)!;
    expect(active.phase, CallPhase.active);
    expect(active.connectedAt, isNotNull);

    // Audio → video, announced to the patient.
    await calls.toggleVideo();
    expect(media.video, isTrue);
    expect(signaling.lastOfType('media'), containsPair('video', true));
    signaling.receive({'type': 'media', 'callId': callId, 'video': true});
    await settle();
    expect(container.read(callControllerProvider)!.remoteVideo, isTrue);

    calls.toggleMute();
    expect(media.muted, isTrue);

    calls.hangUp();
    expect(signaling.lastOfType('hangup')['callId'], callId);
    final ended = container.read(callControllerProvider)!;
    expect(ended.phase, CallPhase.ended);
    expect(ended.endReason, CallEndReason.hungUp);
    await settle();
    expect(media.closed, isTrue);

    // The nurse records the outcome before the screen closes.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(container.read(callControllerProvider), isNotNull);
    calls.dismiss();
    expect(container.read(callControllerProvider), isNull);
  });

  test('patient answers an incoming call: the callee waits for the offer',
      () async {
    final container = containerFor(mockPatient);
    final calls = container.read(callControllerProvider.notifier);
    signaling.receive({
      'type': 'incoming',
      'callId': 'call-1',
      'patientId': kJohnId,
      'escalationId': 'esc-1',
      'video': false,
      'from': {'id': kNurseId, 'role': 'nurse'},
    });
    await settle();
    final ringing = container.read(callControllerProvider)!;
    expect(ringing.phase, CallPhase.incoming);
    expect(ringing.peer.name, 'Triage nurse');

    await calls.accept();
    expect(signaling.lastOfType('accept')['callId'], 'call-1');
    signaling.receive({
      'type': 'accepted',
      'callId': 'call-1',
      'escalationId': 'esc-1',
      'by': {'id': kJohnId, 'role': 'patient'},
    });
    await settle();
    await settle();
    expect(media.initiator, isFalse);

    // The nurse hangs up; the patient's screen closes by itself.
    signaling.receive({'type': 'ended', 'callId': 'call-1', 'reason': 'ended'});
    await settle();
    expect(container.read(callControllerProvider)!.endReason,
        CallEndReason.hungUp);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(container.read(callControllerProvider), isNull);
  });

  test('a call that ends unanswered, busy or denied explains why', () async {
    final container = containerFor(mockNurse);
    final calls = container.read(callControllerProvider.notifier);

    await calls.callPatient(patientId: kJohnId, patientName: 'John Doe');
    var callId = signaling.lastOfType('invite')['callId'];
    signaling.receive({'type': 'ended', 'callId': callId, 'reason': 'missed'});
    await settle();
    expect(container.read(callControllerProvider)!.endReason,
        CallEndReason.missed);
    calls.dismiss();

    await calls.callPatient(patientId: kJohnId, patientName: 'John Doe');
    callId = signaling.lastOfType('invite')['callId'];
    signaling.receive({'type': 'busy', 'callId': callId});
    await settle();
    expect(
        container.read(callControllerProvider)!.endReason, CallEndReason.busy);
    calls.dismiss();

    media.failStart = true;
    await calls.callPatient(patientId: kJohnId, patientName: 'John Doe');
    final failed = container.read(callControllerProvider)!;
    expect(failed.endReason, CallEndReason.failed);
    expect(failed.errorMessage, contains('microphone'));
    calls.dismiss();

    media.failStart = false;
    signaling.connected = false;
    await calls.callPatient(patientId: kJohnId, patientName: 'John Doe');
    expect(container.read(callControllerProvider)!.errorMessage,
        contains('Not connected'));
  });

  test('a second incoming call is ignored while on a call', () async {
    final container = containerFor(mockNurse);
    await container
        .read(callControllerProvider.notifier)
        .callPatient(patientId: kJohnId, patientName: 'John Doe');
    final current = container.read(callControllerProvider)!.callId;
    signaling.receive({
      'type': 'incoming',
      'callId': 'other',
      'patientId': kJaneId,
      'from': {'id': kJaneId, 'role': 'patient'},
    });
    await settle();
    expect(container.read(callControllerProvider)!.callId, current);
  });
}
