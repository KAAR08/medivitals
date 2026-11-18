import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/data/models/user_model.dart';
import '../../features/escalation/data/models/escalation_model.dart';
import '../../features/medical_chat/data/models/chat_message_model.dart';
import '../../features/vitals_monitor/domain/trend.dart';
import '../../features/vitals_monitor/domain/triage.dart';
import 'mock_data.dart';

part 'mock_api_service.g.dart';

/// In-memory stand-in for the backend: returns the same JSON as the real
/// endpoints (so repositories share their `fromJson` code) and throws
/// [ApiException] like [ApiClient].
///
/// Demo data: the login tab picks the account (any password works; an email
/// containing "invalid" fails). Bob has a critical episode every 4 minutes;
/// Jane slowly deteriorates over 10 minutes.
class MockApiService {
  MockApiService() {
    // The engine triages every reading as it arrives; mirror its automatic
    // escalation by checking each patient once per reading interval.
    _autoTriage = Timer.periodic(mockVitalsInterval, (_) => _autoEscalate());
  }

  late final Timer _autoTriage;

  // Simulate network latency
  static const _networkDelay = Duration(milliseconds: 800);

  final Map<String, List<ChatMessage>> _messages = buildMockMessages();
  final Map<String, StreamController<Map<String, dynamic>>> _chatStreams = {};
  final List<Timer> _timers = [];
  int _autoReplyIndex = 0;

  void _log(String msg) => developer.log(msg, name: 'medivitallink.mock_api');

  Future<void> _delay() => Future<void>.delayed(_networkDelay);

  /// POST /auth/login
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    _log('login: email=$email, role=${role.name}');
    await _delay();

    if (email.isEmpty || password.isEmpty || email.contains('invalid')) {
      throw ApiException.server(401, 'Email or password is incorrect');
    }

    final user = switch (role) {
      UserRole.doctor => mockDoctor,
      UserRole.nurse => mockNurse,
      UserRole.patient => mockPatient,
    };
    return {
      'user': user.toJson(),
      'access_token': _accessTokenFor(user.id),
      'refresh_token': 'mock-refresh.${user.id}',
      'expires_in': 600,
    };
  }

  /// POST /auth/logout
  Future<void> logout() async {
    _log('logout');
    await _delay();
  }

  /// GET /auth/me
  Future<Map<String, dynamic>> getCurrentUser(String accessToken) async {
    _log('getCurrentUser');
    await _delay();
    return _userById(_userIdFromToken(accessToken)).toJson();
  }

  String _accessTokenFor(String userId) =>
      'mock-access.$userId.${DateTime.now().millisecondsSinceEpoch}';

  String _userIdFromToken(String accessToken) {
    final parts = accessToken.split('.');
    if (parts.length < 3 || parts.first != 'mock-access') {
      throw ApiException.server(401, 'Access token is invalid');
    }
    return parts[1];
  }

  bool isPatient(String userId) =>
      mockUsers.any((u) => u.id == userId && u.role == UserRole.patient);

  UserModel _userById(String id) {
    for (final u in mockUsers) {
      if (u.id == id) return u;
    }
    throw ApiException.server(404, 'User not found');
  }

  /// GET /patients
  Future<Map<String, dynamic>> getMonitoredPatients() async {
    _log('getMonitoredPatients');
    await _delay();
    return {'patients': mockPatients.map((p) => p.toJson()).toList()};
  }

  /// GET /vitals/:patientId/history
  Future<Map<String, dynamic>> getVitalsHistory(String patientId) async {
    _log('getVitalsHistory: patientId=$patientId');
    await _delay();
    final vitals = generateMockVitals(patientId);
    return {
      'vitals': vitals.map((v) => v.toJson()).toList(),
      'total': vitals.length,
    };
  }

  /// WS /vitals/:patientId/stream — one reading every 5 seconds, starting now.
  Stream<Map<String, dynamic>> streamPatientVitals(String patientId) {
    _log('streamPatientVitals: patientId=$patientId');
    final intervalMs = mockVitalsInterval.inMilliseconds;
    Timer? timer;
    late final StreamController<Map<String, dynamic>> controller;

    void emitAndSchedule() {
      final now = DateTime.now();
      // Live readings carry their real generation time, so the app measures
      // true end-to-end latency.
      controller.add(mockReading(patientId, now, stampAt: now).toJson());
      final untilNextSlot =
          intervalMs - now.millisecondsSinceEpoch % intervalMs;
      timer =
          Timer(Duration(milliseconds: untilNextSlot + 20), emitAndSchedule);
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: emitAndSchedule,
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  /// WS /monitor/stream — every monitored patient's readings, with names.
  Stream<Map<String, dynamic>> streamMonitor() {
    _log('streamMonitor');
    final subs = <StreamSubscription<Map<String, dynamic>>>[];
    late final StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        for (final p in mockPatients) {
          subs.add(streamPatientVitals(p.id).listen(
            controller
                .add, // pseudonymized: IDs only, names come from /patients
          ));
        }
      },
      onCancel: () => Future.wait(subs.map((s) => s.cancel())),
    );
    return controller.stream;
  }

  /// GET /conversations — from the point of view of [userId].
  Future<Map<String, dynamic>> getConversations(String userId) async {
    _log('getConversations: userId=$userId');
    await _delay();

    final conversations = <Map<String, dynamic>>[];
    for (final c in mockConversations) {
      if (c.doctorId != userId && c.patientId != userId) continue;
      final other = _userById(c.doctorId == userId ? c.patientId : c.doctorId);
      final messages = _messages[c.id] ?? const [];
      final last = messages.isEmpty ? null : messages.last;
      conversations.add({
        'id': c.id,
        'participantId': other.id,
        'participantName': other.name,
        if (last != null) 'lastMessage': last.content,
        if (last != null) 'lastMessageTime': last.timestamp.toIso8601String(),
        'unreadCount': 0,
      });
    }
    return {'conversations': conversations};
  }

  /// GET /conversations/:conversationId/messages
  Future<Map<String, dynamic>> getConversationMessages(
      String conversationId) async {
    _log('getConversationMessages: conversationId=$conversationId');
    await _delay();
    _conversation(conversationId);
    return {
      'messages': (_messages[conversationId] ?? const [])
          .map((m) => m.toJson())
          .toList(),
    };
  }

  /// POST /conversations/:conversationId/messages
  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String content,
    required String senderId,
  }) async {
    _log('sendMessage: conversationId=$conversationId');
    if (content.trim().isEmpty) {
      throw ApiException.server(400, 'Message content required');
    }
    final conv = _conversation(conversationId);
    await _delay();

    final message = ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      senderId: senderId,
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );
    _store(conversationId, message);

    // Simulate the recipient's device acknowledging, then replying.
    _later(const Duration(seconds: 1), () {
      final delivered = message.copyWith(status: MessageStatus.delivered);
      _store(conversationId, delivered);
      _push(conversationId, delivered);
    });
    final otherId = conv.doctorId == senderId ? conv.patientId : conv.doctorId;
    _later(const Duration(seconds: 4), () {
      final reply = ChatMessage(
        id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
        senderId: otherId,
        content: mockAutoReplies[_autoReplyIndex++ % mockAutoReplies.length],
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
      );
      _store(conversationId, reply);
      _push(conversationId, reply);
    });

    return message.toJson();
  }

  /// WS /conversations/:conversationId/stream
  Stream<Map<String, dynamic>> streamConversationMessages(
      String conversationId) {
    _log('streamConversationMessages: conversationId=$conversationId');
    return _chatStreams
        .putIfAbsent(
            conversationId, StreamController<Map<String, dynamic>>.broadcast)
        .stream;
  }

  ({String id, String doctorId, String patientId}) _conversation(String id) {
    for (final c in mockConversations) {
      if (c.id == id) return c;
    }
    throw ApiException.server(404, 'Conversation not found');
  }

  void _store(String conversationId, ChatMessage message) {
    final list = _messages.putIfAbsent(conversationId, () => []);
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.add(message);
    }
  }

  void _push(String conversationId, ChatMessage message) {
    final controller = _chatStreams[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add({'type': 'message', ...message.toJson()});
    }
  }

  void _later(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      action();
    });
    _timers.add(timer);
  }

  final Map<String, Escalation> _escalations = {};
  final _escalationStream = StreamController<Map<String, dynamic>>.broadcast();

  /// POST /escalations — the caller asks the triage nurse to call back.
  Future<Map<String, dynamic>> requestCallback({
    required String patientId,
    required EscalationSource source,
    String? note,
  }) async {
    _log('requestCallback: patientId=$patientId source=${source.name}');
    await _delay();
    final open = _openEscalationFor(patientId);
    if (open != null) {
      return open.toJson(); // idempotent: one open request per patient
    }
    return _raise(patientId, source, note: note).toJson();
  }

  /// GET /escalations — open requests (plus recently resolved) visible to [userId].
  Future<Map<String, dynamic>> getEscalations(String userId) async {
    _log('getEscalations: userId=$userId');
    await _delay();
    final user = _userById(userId);
    final visible = _escalations.values.where(
      (e) => user.role != UserRole.patient || e.patientId == userId,
    );
    return {'escalations': visible.map((e) => e.toJson()).toList()};
  }

  /// PATCH /escalations/:id — the care team takes, resolves, refers or
  /// dispatches an ambulance for a case.
  Future<Map<String, dynamic>> updateEscalation({
    required String id,
    required EscalationStatus status,
    required String actorId,
    String? note,
  }) async {
    _log('updateEscalation: id=$id status=${status.name}');
    await _delay();
    final current = _escalations[id];
    if (current == null) throw ApiException.server(404, 'Escalation not found');
    final actor = _userById(actorId);
    if (actor.role == UserRole.patient) {
      throw ApiException.server(
          403, 'Only the care team can update escalations');
    }
    if (!current.status.next.contains(status)) {
      throw ApiException.server(409,
          'Cannot move an escalation from ${current.status.name} to ${status.name}');
    }
    final updated =
        _transition(current, status, actorId, actor.role.name, note: note);
    _escalations[id] = updated;
    _pushEscalation(updated);
    return updated.toJson();
  }

  Escalation _transition(
      Escalation e, EscalationStatus status, String actorId, String role,
      {String? note}) {
    final now = DateTime.now();
    final takes =
        status == EscalationStatus.acknowledged || e.acknowledgedBy == null;
    return e.copyWith(
      status: status,
      acknowledgedBy: takes ? actorId : null,
      acknowledgedAt: takes ? now : null,
      resolvedAt: status == EscalationStatus.resolved ? now : null,
      timeline: [
        ...e.timeline,
        EscalationEvent(
            at: now,
            action: status.name,
            role: role,
            by: actorId,
            note: _blankToNull(note)),
      ],
    );
  }

  /// Notes a finished call on the case (the server does this itself).
  void recordCall(String escalationId,
      {required String callerId,
      required String callerRole,
      required String outcome,
      required int seconds,
      required bool video}) {
    final e = _escalations[escalationId];
    if (e == null) return;
    final updated = e.copyWith(timeline: [
      ...e.timeline,
      EscalationEvent(
        at: DateTime.now(),
        action: 'call',
        role: callerRole,
        by: callerId,
        callOutcome: outcome,
        callSeconds: seconds,
        video: video,
      ),
    ]);
    _escalations[escalationId] = updated;
    _pushEscalation(updated);
  }

  /// The open case a care-team call is about, taken by the caller (as the
  /// server does). Null when the patient has no open case.
  Escalation? takeForCall(String patientId, String actorId, String role) {
    final open = _openEscalationFor(patientId);
    if (open == null) return null;
    if (open.status == EscalationStatus.pending ||
        open.status == EscalationStatus.referred) {
      final taken =
          _transition(open, EscalationStatus.acknowledged, actorId, role);
      _escalations[open.id] = taken;
      _pushEscalation(taken);
      return taken;
    }
    return open;
  }

  static String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// The current state of one case (null if unknown).
  Escalation? escalation(String id) => _escalations[id];

  /// WS /escalations/stream
  Stream<Map<String, dynamic>> streamEscalations() => _escalationStream.stream;

  Escalation? _openEscalationFor(String patientId) {
    for (final e in _escalations.values) {
      if (e.patientId == patientId && e.status.isOpen) return e;
    }
    return null;
  }

  Escalation _raise(String patientId, EscalationSource source, {String? note}) {
    final reading = mockReading(patientId, DateTime.now());
    final escalation = Escalation(
      id: 'esc-${DateTime.now().microsecondsSinceEpoch}',
      patientId: patientId,
      source: source,
      status: EscalationStatus.pending,
      createdAt: DateTime.now(),
      severity: reading.severity,
      alerts: reading.alerts,
      note: note,
      timeline: [
        EscalationEvent(
          at: DateTime.now(),
          action: 'raised',
          role: source.name,
          by: source == EscalationSource.auto ? null : patientId,
          note: note,
        ),
      ],
    );
    _escalations[escalation.id] = escalation;
    _pushEscalation(escalation);
    return escalation;
  }

  void _autoEscalate() {
    for (final p in mockPatients) {
      if (_openEscalationFor(p.id) != null) continue;
      final reading = mockReading(p.id, DateTime.now());
      if (reading.severity == Severity.critical) {
        _raise(p.id, EscalationSource.auto,
            note: 'Automatic: critical reading');
      } else if (trendAlertCount(reading.alerts) >= 2) {
        _raise(p.id, EscalationSource.auto,
            note: 'Early warning: several vitals deteriorating together');
      }
    }
  }

  void _pushEscalation(Escalation e) {
    if (!_escalationStream.isClosed) {
      _escalationStream.add({'type': 'escalation', ...e.toJson()});
    }
  }

  void dispose() {
    _autoTriage.cancel();
    _escalationStream.close();
    for (final t in _timers) {
      t.cancel();
    }
    for (final c in _chatStreams.values) {
      c.close();
    }
  }
}

@Riverpod(keepAlive: true)
MockApiService mockApiService(Ref ref) {
  final service = MockApiService();
  ref.onDispose(service.dispose);
  return service;
}
