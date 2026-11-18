import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/time_ago.dart';
import '../../../vitals_monitor/data/repositories/vitals_repository.dart';
import '../../../vitals_monitor/presentation/widgets/health_banner.dart';
import '../../../calls/presentation/viewmodels/call_controller.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../data/models/escalation_model.dart';
import '../viewmodels/escalation_viewmodel.dart';
import 'case_outcome_form.dart';

/// Every open case, most urgent first. Nurses land here; doctors open it
/// from their monitor for the cases referred to them.
class TriageQueueView extends ConsumerWidget {
  const TriageQueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final escalations = ref.watch(escalationsProvider);
    final queue = ref.watch(triageQueueProvider);
    final pending = ref.watch(pendingEscalationCountProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(ref.watch(currentUserProvider)?.role == UserRole.doctor
            ? 'Cases'
            : 'Triage queue'),
        // Doctors reach this screen from their monitor; the nurse lands here.
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              pending == 0
                  ? 'No new cases waiting'
                  : '$pending new case${pending == 1 ? '' : 's'} waiting',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: () => ref.refresh(escalationsProvider.future),
              child: switch (escalations) {
                AsyncError(:final error) when queue.isEmpty => _Message(
                    icon: Icons.cloud_off_outlined,
                    text: error is ApiException
                        ? error.message
                        : 'Could not load the queue.',
                  ),
                AsyncData() when queue.isEmpty => const _Message(
                    icon: Icons.inbox_outlined,
                    text: 'No open cases.',
                  ),
                AsyncLoading() when queue.isEmpty =>
                  const Center(child: CircularProgressIndicator()),
                _ => ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) =>
                        _EscalationCard(escalation: queue[i]),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EscalationCard extends ConsumerStatefulWidget {
  const _EscalationCard({required this.escalation});
  final Escalation escalation;

  @override
  ConsumerState<_EscalationCard> createState() => _EscalationCardState();
}

class _EscalationCardState extends ConsumerState<_EscalationCard> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = widget.escalation;
    final onCall = ref.watch(callControllerProvider)?.isLive ?? false;
    final resolved = e.status == EscalationStatus.resolved;

    return Opacity(
      opacity: resolved ? 0.6 : 1,
      child: DecoratedBox(
        decoration: context.card(),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push(AppRoutes.patientDetailPath(e.patientId)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _patientName(ref, e.patientId),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (e.status == EscalationStatus.ambulance ||
                          e.status == EscalationStatus.referred) ...[
                        _StatusTag(status: e.status),
                        const SizedBox(width: 6),
                      ],
                      SeverityChip(severity: e.severity),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_source(e)} · ${timeAgo(e.createdAt)} · ${_statusLabel(e.status)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final alert in e.alerts.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $alert',
                          style: TextStyle(fontSize: 12, color: c.textPrimary)),
                    ),
                  if (e.outcomeNote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('“${e.outcomeNote}”',
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: c.textSecondary)),
                    ),
                  if (_lastCall(e) case final call?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(call,
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                  if (!resolved) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: onCall
                                ? null
                                : () => ref
                                    .read(callControllerProvider.notifier)
                                    .callPatient(
                                      patientId: e.patientId,
                                      patientName:
                                          _patientName(ref, e.patientId),
                                      escalationId: e.id,
                                    ),
                            style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44)),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: const Text('Call patient'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                showCaseOutcomeSheet(context, e.id),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44)),
                            icon: const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 18),
                            label: const Text('Outcome'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Last call: answered, 2 min 10 s" / "Last call: no answer".
  static String? _lastCall(Escalation e) {
    final call = e.timeline.where((t) => t.action == 'call').lastOrNull;
    if (call == null) return null;
    final who = call.role == 'patient' ? 'Patient called' : 'Last call';
    final kind = call.video ? 'video' : 'voice';
    return switch (call.callOutcome) {
      'answered' =>
        '$who: $kind, ${call.callSeconds! ~/ 60} min ${call.callSeconds! % 60} s',
      'declined' => '$who: declined',
      'cancelled' => '$who: hung up before an answer',
      _ => '$who: no answer',
    };
  }

  /// Why the case exists, in the queue's shorthand.
  static String _source(Escalation e) => switch (e.source) {
        EscalationSource.auto => (e.note ?? '').startsWith('Early warning')
            ? 'Auto · early warning'
            : 'Auto · critical reading',
        _ => 'Patient request',
      };

  static String _statusLabel(EscalationStatus s) => switch (s) {
        EscalationStatus.pending => 'Waiting',
        EscalationStatus.acknowledged => 'Being handled',
        EscalationStatus.referred => 'Referred to a doctor',
        EscalationStatus.ambulance => 'Ambulance dispatched',
        EscalationStatus.resolved => 'Resolved',
      };

  /// Telemetry carries only pseudonymized IDs; names are joined in here
  /// from the identity service's patient list.
  static String _patientName(WidgetRef ref, String patientId) {
    final patients =
        ref.watch(monitoredPatientsProvider).valueOrNull ?? const [];
    for (final p in patients) {
      if (p.id == patientId) return p.name;
    }
    return 'Patient ${patientId.substring(0, 8)}';
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});
  final EscalationStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ambulance = status == EscalationStatus.ambulance;
    final color = ambulance ? c.critical : c.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ambulance ? c.criticalLight : c.warningLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              ambulance
                  ? Icons.local_hospital_rounded
                  : Icons.medical_services_rounded,
              size: 13,
              color: color),
          const SizedBox(width: 4),
          Text(ambulance ? 'Ambulance' : 'Referred',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 48, color: context.colors.textTertiary),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
