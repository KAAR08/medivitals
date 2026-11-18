import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../data/models/escalation_model.dart';
import '../../data/repositories/escalation_repository.dart';

part 'escalation_viewmodel.g.dart';

/// Every case the signed-in user may see, kept current by the server's
/// stream. Actions throw [ApiException] for the screen to show.
@riverpod
class Escalations extends _$Escalations {
  @override
  Future<List<Escalation>> build() async {
    ref.watch(currentUserProvider); // reload when a different user signs in
    final repo = ref.watch(escalationRepositoryProvider);

    // Subscribe before loading so nothing raised during the load is missed.
    final sub = repo.watch().listen(_upsert);
    ref.onDispose(sub.cancel);

    return repo.fetchAll();
  }

  /// Single-tap escalation: ask the triage nurse to call [patientId].
  Future<void> requestCallback(String patientId) async {
    final escalation =
        await ref.read(escalationRepositoryProvider).requestCallback(
              patientId: patientId,
              source: EscalationSource.patient,
            );
    _upsert(escalation);
  }

  /// Care team: take the case without calling (calling takes it automatically).
  Future<void> acknowledge(String id) =>
      recordOutcome(id, EscalationStatus.acknowledged);

  /// Care team: resolve, refer to a doctor, or dispatch an ambulance.
  Future<void> recordOutcome(String id, EscalationStatus status,
      {String? note}) async {
    _upsert(await ref
        .read(escalationRepositoryProvider)
        .updateStatus(id, status, note: note));
  }

  void _upsert(Escalation e) {
    final current = state.valueOrNull;
    if (current == null) return; // the initial load will include it
    state = AsyncData([
      for (final x in current)
        if (x.id != e.id) x,
      e,
    ]);
  }
}

/// The triage queue: ambulance cases and new requests first, then cases being
/// handled; most severe first, then oldest first; resolved ones last, newest
/// first.
@riverpod
List<Escalation> triageQueue(Ref ref) {
  final all = ref.watch(escalationsProvider).valueOrNull ?? const [];
  int rank(Escalation e) => switch (e.status) {
        EscalationStatus.ambulance => 0,
        EscalationStatus.pending => 1,
        EscalationStatus.referred => 2,
        EscalationStatus.acknowledged => 3,
        EscalationStatus.resolved => 4,
      };
  return [...all]..sort((a, b) {
      final byStatus = rank(a).compareTo(rank(b));
      if (byStatus != 0) return byStatus;
      if (a.status == EscalationStatus.resolved) {
        return b.createdAt.compareTo(a.createdAt);
      }
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      return bySeverity != 0 ? bySeverity : a.createdAt.compareTo(b.createdAt);
    });
}

/// Cases referred to a doctor, or with an ambulance on the way, not yet
/// resolved: what a doctor needs to look at.
@riverpod
List<Escalation> referrals(Ref ref) => ref
    .watch(triageQueueProvider)
    .where((e) =>
        e.status == EscalationStatus.referred ||
        e.status == EscalationStatus.ambulance)
    .toList();

/// Number of requests still waiting for a nurse — for badges.
@riverpod
int pendingEscalationCount(Ref ref) => ref
    .watch(triageQueueProvider)
    .where((e) => e.status == EscalationStatus.pending)
    .length;

/// The patient's most recent request, or null if they have never asked.
@riverpod
Escalation? latestEscalationFor(Ref ref, String patientId) {
  final all = ref.watch(escalationsProvider).valueOrNull ?? const [];
  Escalation? latest;
  for (final e in all) {
    if (e.patientId != patientId) continue;
    if (latest == null || e.createdAt.isAfter(latest.createdAt)) latest = e;
  }
  return latest;
}
