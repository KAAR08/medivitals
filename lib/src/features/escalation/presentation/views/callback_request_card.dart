import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/time_ago.dart';
import '../../data/models/escalation_model.dart';
import '../viewmodels/escalation_viewmodel.dart';

/// Asks the triage nurse to call back, then shows where the case stands.
/// Patients can't ring nurses directly: the nurse works her queue, most
/// urgent first, so she isn't interrupted mid-call.
class CallbackRequestCard extends ConsumerStatefulWidget {
  const CallbackRequestCard({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<CallbackRequestCard> createState() =>
      _CallbackRequestCardState();
}

class _CallbackRequestCardState extends ConsumerState<CallbackRequestCard> {
  bool _sending = false;

  Future<void> _request() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(escalationsProvider.notifier)
          .requestCallback(widget.patientId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message),
              backgroundColor: context.colors.critical),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final latest = ref.watch(latestEscalationForProvider(widget.patientId));
    final open = latest != null && latest.status.isOpen ? latest : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Need help?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A triage nurse will call you back. Keep the app open to answer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (open == null)
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _request,
                style: ElevatedButton.styleFrom(backgroundColor: c.critical),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.phone_callback_rounded),
                label: Text(_sending ? 'Sending…' : 'Request a callback'),
              ),
            )
          else
            _RequestStatus(escalation: open),
          if (open == null && latest?.status == EscalationStatus.resolved) ...[
            const SizedBox(height: 8),
            Text(
              'Your last request was resolved.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestStatus extends StatelessWidget {
  const _RequestStatus({required this.escalation});
  final Escalation escalation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = timeAgo(escalation.createdAt);

    final (
      IconData icon,
      Color color,
      Color background,
      String title,
      String detail
    ) = switch (escalation.status) {
      EscalationStatus.ambulance => (
          Icons.local_hospital_rounded,
          c.critical,
          c.criticalLight,
          'Ambulance dispatched',
          'Stay where you are, keep your phone with you and unlock your door if you can. '
              '(Simulation: no real ambulance is sent.)',
        ),
      EscalationStatus.referred => (
          Icons.medical_services_rounded,
          c.warning,
          c.warningLight,
          'Referred to a doctor',
          'The nurse has asked a doctor to review your case. They will call you.',
        ),
      EscalationStatus.acknowledged => (
          Icons.phone_in_talk_rounded,
          c.success,
          c.successLight,
          'A nurse is handling your case',
          'Keep your phone nearby.',
        ),
      _ => (
          Icons.schedule_rounded,
          c.warning,
          c.warningLight,
          'Callback requested',
          escalation.source == EscalationSource.auto
              ? 'Raised automatically $when after a critical reading.'
              : 'Sent $when, waiting for the triage nurse.',
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, color: color)),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
