import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../data/services/mock_api_service.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../models/escalation_model.dart';

part 'escalation_repository.g.dart';

/// Nurse-callback requests. Futures throw [ApiException].
abstract interface class EscalationRepository {
  /// Raises (or returns the already-open) callback request for [patientId].
  Future<Escalation> requestCallback({
    required String patientId,
    required EscalationSource source,
    String? note,
  });

  /// Requests the signed-in user may see (a patient: only their own).
  Future<List<Escalation>> fetchAll();

  /// Care team only: take the case, resolve it, refer it to a doctor or
  /// dispatch an ambulance. [note] records why (stored encrypted).
  Future<Escalation> updateStatus(String id, EscalationStatus status,
      {String? note});

  /// New and changed requests, pushed by the server.
  Stream<Escalation> watch();
}

List<Escalation> _parseList(Map<String, dynamic> json) =>
    (json['escalations'] as List<dynamic>)
        .map((e) => Escalation.fromJson(e as Map<String, dynamic>))
        .toList();

Stream<Escalation> _parseEvents(Stream<Map<String, dynamic>> raw) {
  return raw.transform(StreamTransformer.fromHandlers(handleData: (json, sink) {
    if ((json['type'] as String? ?? 'escalation') != 'escalation') return;
    try {
      sink.add(Escalation.fromJson(json));
    } catch (e) {
      developer.log('Dropping malformed escalation event: $json',
          name: 'medivitallink.escalation', error: e);
    }
  }));
}

class RemoteEscalationRepository implements EscalationRepository {
  const RemoteEscalationRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String? Function() _accessToken;

  @override
  Future<Escalation> requestCallback({
    required String patientId,
    required EscalationSource source,
    String? note,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/escalations',
      data: {
        'patientId': patientId,
        'source': source.name,
        if (note != null) 'note': note
      },
    );
    return Escalation.fromJson(response.data!);
  }

  @override
  Future<List<Escalation>> fetchAll() async {
    final response = await _apiClient.get<Map<String, dynamic>>('/escalations');
    return _parseList(response.data!);
  }

  @override
  Future<Escalation> updateStatus(String id, EscalationStatus status,
      {String? note}) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '/escalations/$id',
      data: {
        'status': status.name,
        if (note != null && note.isNotEmpty) 'note': note
      },
    );
    return Escalation.fromJson(response.data!);
  }

  @override
  Stream<Escalation> watch() {
    return _parseEvents(WebSocketClient.jsonStream(() {
      final token = _accessToken();
      final query =
          token == null ? '' : '?token=${Uri.encodeQueryComponent(token)}';
      return '${AppConfig.wsBaseUrl}/escalations/stream$query';
    }));
  }
}

class MockEscalationRepository implements EscalationRepository {
  const MockEscalationRepository(this._api, this._currentUserId);

  final MockApiService _api;
  final String? Function() _currentUserId;

  String get _userId {
    final id = _currentUserId();
    if (id == null) throw ApiException.server(401, 'Not signed in');
    return id;
  }

  @override
  Future<Escalation> requestCallback({
    required String patientId,
    required EscalationSource source,
    String? note,
  }) async =>
      Escalation.fromJson(await _api.requestCallback(
          patientId: patientId, source: source, note: note));

  @override
  Future<List<Escalation>> fetchAll() async =>
      _parseList(await _api.getEscalations(_userId));

  @override
  Future<Escalation> updateStatus(String id, EscalationStatus status,
          {String? note}) async =>
      Escalation.fromJson(await _api.updateEscalation(
          id: id, status: status, actorId: _userId, note: note));

  @override
  Stream<Escalation> watch() {
    // Same visibility rule as the server: patients only see their own.
    final userId = _currentUserId();
    final ownOnly = userId != null && _api.isPatient(userId);
    return _parseEvents(_api.streamEscalations())
        .where((e) => !ownOnly || e.patientId == userId);
  }
}

@Riverpod(keepAlive: true)
EscalationRepository escalationRepository(Ref ref) {
  if (AppConfig.useMockBackend) {
    return MockEscalationRepository(
      ref.watch(mockApiServiceProvider),
      () => ref.read(authViewModelProvider).session?.user.id,
    );
  }
  return RemoteEscalationRepository(
    ref.watch(apiClientProvider),
    () => ref.read(authViewModelProvider).session?.accessToken,
  );
}
