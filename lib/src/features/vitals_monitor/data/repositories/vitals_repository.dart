import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../data/services/mock_api_service.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../models/patient_summary.dart';
import '../models/vitals_model.dart';

part 'vitals_repository.g.dart';

/// Monitored patients and their vitals, as history (REST) and live streams.
/// Futures throw [ApiException]; streams silently skip malformed events.
abstract interface class VitalsRepository {
  /// Patients the signed-in doctor monitors.
  Future<List<PatientSummary>> fetchMonitoredPatients();

  /// Recent readings for one patient, oldest first.
  Future<List<VitalsSnapshot>> fetchHistory(String patientId);

  /// Live readings for one patient.
  Stream<VitalsSnapshot> watchPatient(String patientId);

  /// Live readings for every monitored patient, with the patient's name.
  Stream<({VitalsSnapshot snapshot, String? patientName})> watchAllPatients();
}

List<PatientSummary> _parsePatients(Map<String, dynamic> json) =>
    (json['patients'] as List<dynamic>)
        .map((p) => PatientSummary.fromJson(p as Map<String, dynamic>))
        .toList();

List<VitalsSnapshot> _parseHistory(Map<String, dynamic> json) =>
    (json['vitals'] as List<dynamic>)
        .map((v) => VitalsSnapshot.fromJson(v as Map<String, dynamic>))
        .toList();

/// Maps a raw event stream to snapshots, logging and dropping bad events.
Stream<T> _parseEach<T>(
    Stream<Map<String, dynamic>> raw, T Function(Map<String, dynamic>) parse) {
  return raw.transform(StreamTransformer.fromHandlers(handleData: (json, sink) {
    try {
      sink.add(parse(json));
    } catch (e) {
      developer.log('Dropping malformed vitals event: $json',
          name: 'medivitallink.vitals', error: e);
    }
  }));
}

({VitalsSnapshot snapshot, String? patientName}) _parseMonitorEvent(
        Map<String, dynamic> json) =>
    (
      snapshot: VitalsSnapshot.fromJson(json),
      patientName: json['patientName'] as String?
    );

class RemoteVitalsRepository implements VitalsRepository {
  const RemoteVitalsRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String? Function() _accessToken;

  @override
  Future<List<PatientSummary>> fetchMonitoredPatients() async {
    final response = await _apiClient.get<Map<String, dynamic>>('/patients');
    return _parsePatients(response.data!);
  }

  @override
  Future<List<VitalsSnapshot>> fetchHistory(String patientId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/vitals/$patientId/history',
      queryParameters: {'limit': 60},
    );
    return _parseHistory(response.data!);
  }

  @override
  Stream<VitalsSnapshot> watchPatient(String patientId) => _parseEach(
        WebSocketClient.jsonStream(() => _wsUrl('/vitals/$patientId/stream')),
        VitalsSnapshot.fromJson,
      );

  @override
  Stream<({VitalsSnapshot snapshot, String? patientName})> watchAllPatients() =>
      _parseEach(
        WebSocketClient.jsonStream(() => _wsUrl('/monitor/stream')),
        _parseMonitorEvent,
      );

  /// Builds the socket URL with the *current* token (re-read on reconnect).
  String _wsUrl(String path) {
    final token = _accessToken();
    final query =
        token == null ? '' : '?token=${Uri.encodeQueryComponent(token)}';
    return '${AppConfig.wsBaseUrl}$path$query';
  }
}

class MockVitalsRepository implements VitalsRepository {
  const MockVitalsRepository(this._api);

  final MockApiService _api;

  @override
  Future<List<PatientSummary>> fetchMonitoredPatients() async =>
      _parsePatients(await _api.getMonitoredPatients());

  @override
  Future<List<VitalsSnapshot>> fetchHistory(String patientId) async =>
      _parseHistory(await _api.getVitalsHistory(patientId));

  @override
  Stream<VitalsSnapshot> watchPatient(String patientId) =>
      _parseEach(_api.streamPatientVitals(patientId), VitalsSnapshot.fromJson);

  @override
  Stream<({VitalsSnapshot snapshot, String? patientName})> watchAllPatients() =>
      _parseEach(_api.streamMonitor(), _parseMonitorEvent);
}

@Riverpod(keepAlive: true)
VitalsRepository vitalsRepository(Ref ref) {
  if (AppConfig.useMockBackend) {
    return MockVitalsRepository(ref.watch(mockApiServiceProvider));
  }
  return RemoteVitalsRepository(
    ref.watch(apiClientProvider),
    () => ref.read(authViewModelProvider).session?.accessToken,
  );
}

/// The doctor's patient list (also used to name patients on detail screens).
@riverpod
Future<List<PatientSummary>> monitoredPatients(Ref ref) =>
    ref.watch(vitalsRepositoryProvider).fetchMonitoredPatients();
