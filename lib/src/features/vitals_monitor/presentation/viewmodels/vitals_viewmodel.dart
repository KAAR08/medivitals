import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/api_client.dart';
import '../../data/models/vitals_model.dart';
import '../../data/repositories/vitals_repository.dart';

part 'vitals_viewmodel.g.dart';

const int _maxHistoryPoints = 60;

/// Stamps a live reading with its arrival time, for latency measurement.
VitalsSnapshot _received(VitalsSnapshot s) =>
    s.copyWith(receivedAt: DateTime.now());

List<VitalsSnapshot> _append(
    List<VitalsSnapshot> history, VitalsSnapshot s, int max) {
  // Ignore duplicates/out-of-order readings (e.g. a live event that is
  // already the last point of freshly loaded history).
  if (history.isNotEmpty && !s.timestamp.isAfter(history.last.timestamp)) {
    return history;
  }
  final updated = [...history, s];
  return updated.length > max ? updated.sublist(updated.length - max) : updated;
}

@riverpod
class VitalsViewModel extends _$VitalsViewModel {
  // Bumped on dispose so late async results from a previous build are ignored.
  int _generation = 0;

  @override
  PatientVitalsState build(String patientId) {
    final gen = _generation;
    final repo = ref.watch(vitalsRepositoryProvider);

    final sub = repo.watchPatient(patientId).listen(
      (snapshot) {
        if (gen != _generation) return;
        final live = _received(snapshot);
        state = state.copyWith(
          history: _append(state.history, live, _maxHistoryPoints),
          latest: live,
          isConnected: true,
        );
      },
      onError: (Object _) {
        if (gen == _generation) state = state.copyWith(isConnected: false);
      },
    );
    ref.onDispose(() {
      _generation++;
      sub.cancel();
    });

    Future.microtask(() => _loadHistory(gen));
    return PatientVitalsState(patientId: patientId, patientName: '');
  }

  /// Pull-to-refresh: reloads the history.
  Future<void> refresh() => _loadHistory(_generation);

  Future<void> _loadHistory(int gen) async {
    try {
      final history =
          await ref.read(vitalsRepositoryProvider).fetchHistory(patientId);
      if (gen != _generation) return;

      // Keep any live readings that arrived while the history was loading.
      var merged = history;
      for (final live in state.history) {
        merged = _append(merged, live, _maxHistoryPoints);
      }
      state = state.copyWith(
        history: merged,
        latest: merged.isEmpty ? null : merged.last,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (gen == _generation) state = state.copyWith(errorMessage: e.message);
    }
  }
}

@riverpod
class DoctorMonitorViewModel extends _$DoctorMonitorViewModel {
  static const _maxHistoryPerPatient = 30;
  int _generation = 0;

  @override
  DoctorMonitorState build() {
    final gen = _generation;
    final repo = ref.watch(vitalsRepositoryProvider);

    final sub = repo.watchAllPatients().listen(
      (event) {
        if (gen == _generation) _onReading(event.snapshot, event.patientName);
      },
      onError: (Object _) {
        if (gen == _generation) state = state.copyWith(isConnected: false);
      },
    );
    ref.onDispose(() {
      _generation++;
      sub.cancel();
    });

    Future.microtask(() => _seedPatients(gen));
    return const DoctorMonitorState();
  }

  /// Display names from the identity service. Telemetry is pseudonymized
  /// (UUIDs only), so names are joined in here.
  final Map<String, String> _names = {};

  /// Shows a card for every monitored patient before their first reading,
  /// and names any card whose readings arrived before this list did.
  Future<void> _seedPatients(int gen) async {
    try {
      final patients =
          await ref.read(vitalsRepositoryProvider).fetchMonitoredPatients();
      if (gen != _generation) return;
      _names
        ..clear()
        ..addAll({for (final p in patients) p.id: p.name});
      state = state.copyWith(patients: {
        for (final p in patients)
          p.id: PatientVitalsState(patientId: p.id, patientName: p.name),
        for (final e in state.patients.entries)
          e.key: e.value
              .copyWith(patientName: _names[e.key] ?? e.value.patientName),
      });
    } on ApiException catch (_) {
      // Cards will still appear as soon as each patient's readings arrive.
    }
  }

  void _onReading(VitalsSnapshot snapshot, String? patientName) {
    final live = _received(snapshot);
    final current = state.patients[snapshot.patientId] ??
        PatientVitalsState(
          patientId: snapshot.patientId,
          patientName: _names[snapshot.patientId] ??
              patientName ??
              'Patient ${snapshot.patientId.substring(0, 8)}',
        );

    final updated = current.copyWith(
      history: _append(current.history, live, _maxHistoryPerPatient),
      latest: live,
      isConnected: true,
    );

    state = state.copyWith(
      patients: {...state.patients, snapshot.patientId: updated},
      isConnected: true,
    );
  }
}
