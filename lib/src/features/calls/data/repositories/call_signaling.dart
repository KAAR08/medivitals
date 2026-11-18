import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../data/services/mock_api_service.dart';
import '../../../../data/services/mock_data.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../../escalation/data/models/escalation_model.dart';

part 'call_signaling.g.dart';

/// The call signalling channel (Telemetry Engine `/calls/signal`).
///
/// Messages are JSON maps with a `type`: the app sends invite / accept /
/// decline / hangup / signal / media, and receives ringing / incoming /
/// accepted / taken / busy / ended / signal / media / error.
abstract interface class CallSignaling {
  /// Messages for the signed-in user. Connects on listen, disconnects on cancel.
  Stream<Map<String, dynamic>> connect();

  /// False if the message couldn't be sent (not connected).
  bool send(Map<String, dynamic> message);

  /// STUN/TURN servers for WebRTC.
  Future<List<Map<String, dynamic>>> iceServers();

  /// True for the mock backend: the other side is simulated, no media flows.
  bool get simulated;
}

class RemoteCallSignaling implements CallSignaling {
  RemoteCallSignaling(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String? Function() _accessToken;
  WebSocketClient? _client;

  @override
  bool get simulated => false;

  @override
  Stream<Map<String, dynamic>> connect() {
    StreamSubscription<Map<String, dynamic>>? forward;
    late final StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        final client = _client = WebSocketClient();
        forward = client.messageStream.listen(controller.add);
        client.connect(() {
          final token = _accessToken();
          final query =
              token == null ? '' : '?token=${Uri.encodeQueryComponent(token)}';
          return '${AppConfig.wsBaseUrl}/calls/signal$query';
        });
      },
      onCancel: () async {
        await forward?.cancel();
        await _client?.dispose();
        _client = null;
      },
    );
    return controller.stream;
  }

  @override
  bool send(Map<String, dynamic> message) => _client?.send(message) ?? false;

  @override
  Future<List<Map<String, dynamic>>> iceServers() async {
    final response =
        await _apiClient.get<Map<String, dynamic>>('/calls/ice-servers');
    return (response.data!['iceServers'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }
}

/// Simulates the person at the other end, so calls can be demonstrated
/// without a backend:
/// - a call the user places is answered after a couple of seconds;
/// - a patient who requests a callback is rung by the triage nurse shortly
///   after, as a real nurse working the queue would.
class MockCallSignaling implements CallSignaling {
  MockCallSignaling(this._api, this._user,
      {this.answerDelay = const Duration(milliseconds: 2500)});

  final MockApiService _api;
  final UserModel _user;
  final Duration answerDelay;

  /// How long after a callback request the simulated nurse calls back.
  static const callbackDelay = Duration(seconds: 8);
  static const _ringTimeout = Duration(seconds: 30);

  final _out = StreamController<Map<String, dynamic>>.broadcast();
  final _timers = <String, Timer>{};
  final _calls = <String, _MockCall>{};
  StreamSubscription<Map<String, dynamic>>? _escalationWatch;

  @override
  bool get simulated => true;

  @override
  Stream<Map<String, dynamic>> connect() {
    if (_user.role == UserRole.patient) {
      _escalationWatch ??= _api.streamEscalations().listen(_callBackOnRequest);
    }
    late final StreamController<Map<String, dynamic>> controller;
    StreamSubscription<Map<String, dynamic>>? forward;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () => forward = _out.stream.listen(controller.add),
      onCancel: () async {
        for (final t in _timers.values) {
          t.cancel();
        }
        _timers.clear();
        final watch = _escalationWatch;
        _escalationWatch = null;
        await forward?.cancel();
        await watch?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() async => const [];

  @override
  bool send(Map<String, dynamic> message) {
    final callId = message['callId'] as String? ?? '';
    switch (message['type']) {
      case 'invite':
        _invite(callId, message['to'] as String,
            message['escalationId'] as String?);
      case 'accept':
        final call = _calls[callId];
        if (call != null) {
          call.answeredAt = DateTime.now();
          _timers.remove(callId)?.cancel();
          _emit({
            'type': 'accepted',
            'callId': callId,
            'patientId': call.patientId,
            'escalationId': call.escalationId,
            'video': false,
            'by': {'id': _user.id, 'role': _user.role.name},
          });
        }
      case 'decline':
        _finish(callId, 'declined');
      case 'hangup':
        final call = _calls[callId];
        _finish(callId, call?.answeredAt == null ? 'cancelled' : 'answered');
      case 'media':
        final call = _calls[callId];
        if (call != null && message['video'] == true) call.video = true;
    }
    return true;
  }

  void _invite(String callId, String patientId, String? escalationId) {
    final call = _calls[callId] = _MockCall(
      patientId: patientId,
      callerId: _user.id,
      callerRole: _user.role.name,
      escalationId: escalationId,
    );
    _emit({
      'type': 'ringing',
      'callId': callId,
      'patientId': patientId,
      'escalationId': escalationId
    });
    _timers[callId] = Timer(answerDelay, () {
      _timers.remove(callId);
      final esc = _api.takeForCall(patientId, _user.id, _user.role.name);
      call
        ..escalationId = esc?.id ?? call.escalationId
        ..answeredAt = DateTime.now();
      _emit({
        'type': 'accepted',
        'callId': callId,
        'patientId': patientId,
        'escalationId': call.escalationId,
        'video': false,
        'by': {'id': patientId, 'role': 'patient'},
      });
    });
  }

  /// A patient's new callback request: the simulated nurse calls back.
  void _callBackOnRequest(Map<String, dynamic> event) {
    final esc = Escalation.fromJson(event);
    final requestedNow = esc.status == EscalationStatus.pending &&
        esc.patientId == _user.id &&
        esc.timeline.length <= 1;
    if (!requestedNow ||
        _calls.isNotEmpty ||
        _timers.containsKey('callback-${esc.id}')) return;
    _timers['callback-${esc.id}'] = Timer(callbackDelay, () {
      _timers.remove('callback-${esc.id}');
      // Only if it is still waiting, and never on top of a call in progress.
      if (_api.escalation(esc.id)?.status != EscalationStatus.pending ||
          _calls.isNotEmpty) return;
      final callId = const Uuid().v4();
      final taken = _api.takeForCall(_user.id, kNurseId, UserRole.nurse.name);
      _calls[callId] = _MockCall(
        patientId: _user.id,
        callerId: kNurseId,
        callerRole: UserRole.nurse.name,
        escalationId: taken?.id ?? esc.id,
      );
      _emit({
        'type': 'incoming',
        'callId': callId,
        'patientId': _user.id,
        'escalationId': taken?.id ?? esc.id,
        'video': false,
        'from': {'id': kNurseId, 'role': 'nurse'},
      });
      _timers[callId] =
          Timer(_ringTimeout, () => _finish(callId, 'missed', notify: true));
    });
  }

  void _finish(String callId, String outcome, {bool notify = false}) {
    _timers.remove(callId)?.cancel();
    final call = _calls.remove(callId);
    if (call == null) return;
    final escalationId = call.escalationId;
    if (escalationId != null) {
      final answeredAt = call.answeredAt;
      _api.recordCall(
        escalationId,
        callerId: call.callerId,
        callerRole: call.callerRole,
        outcome: outcome,
        seconds: answeredAt == null
            ? 0
            : DateTime.now().difference(answeredAt).inSeconds,
        video: call.video,
      );
    }
    if (notify) _emit({'type': 'ended', 'callId': callId, 'reason': outcome});
  }

  void _emit(Map<String, dynamic> message) {
    if (!_out.isClosed) _out.add(message);
  }
}

class _MockCall {
  _MockCall({
    required this.patientId,
    required this.callerId,
    required this.callerRole,
    this.escalationId,
  });

  final String patientId;
  final String callerId;
  final String callerRole;
  String? escalationId;
  DateTime? answeredAt;
  bool video = false;
}

/// The signalling channel for the signed-in user (null when signed out).
@riverpod
CallSignaling? callSignaling(Ref ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  if (AppConfig.useMockBackend) {
    return MockCallSignaling(ref.watch(mockApiServiceProvider), user);
  }
  return RemoteCallSignaling(
    ref.watch(apiClientProvider),
    () => ref.read(authViewModelProvider).session?.accessToken,
  );
}
