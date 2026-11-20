import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/triage.dart';

/// Colours, icon and wording for each triage level.
({Color fg, Color bg, Color border, IconData icon, String label}) severityStyle(
    BuildContext context, Severity severity) {
  final c = context.colors;
  return switch (severity) {
    Severity.stable => (
        fg: c.success,
        bg: c.successLight,
        border: c.success.fade(0.35),
        icon: Icons.check_circle_rounded,
        label: 'Stable',
      ),
    Severity.warning => (
        fg: c.warning,
        bg: c.warningLight,
        border: c.warning.fade(0.4),
        icon: Icons.visibility_rounded,
        label: 'Monitor closely',
      ),
    Severity.critical => (
        fg: c.critical,
        bg: c.criticalLight,
        border: c.criticalBorder,
        icon: Icons.warning_rounded,
        label: 'Action required',
      ),
  };
}

/// Green "Stable", amber "Monitor closely" or red "Action required", with the
/// reasons.
/// Lists the triage reasons so the patient or clinician sees *why*.
class HealthBanner extends StatelessWidget {
  const HealthBanner(
      {super.key, required this.severity, this.alerts = const []});

  final Severity severity;
  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    final s = severityStyle(context, severity);
    final message = switch (severity) {
      Severity.stable =>
        'All vital signs are within the expected recovery range.',
      Severity.warning =>
        'Some readings are outside the normal range. Keep resting and watch for symptoms.',
      Severity.critical =>
        'Readings need urgent clinical attention. The care team has been alerted.',
    };

    final critical = severity == Severity.critical;
    return Semantics(
      liveRegion: true,
      label: 'Health status: ${s.label}',
      // A neutral card with a coloured bar; critical alone is tinted red so it
      // can't be missed.
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: context.card(color: critical ? s.bg : null),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: s.fg),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(s.icon, color: s.fg, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.label,
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: s.fg),
                            ),
                            const SizedBox(height: 4),
                            Text(message,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: context.colors.textSecondary)),
                            for (final alert in alerts) ...[
                              const SizedBox(height: 4),
                              Text(
                                '• $alert',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: critical
                                      ? s.fg
                                      : context.colors.textPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact severity label for cards and lists.
class SeverityChip extends StatelessWidget {
  const SeverityChip({super.key, required this.severity});

  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final s = severityStyle(context, severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 12, color: s.fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: s.fg),
            ),
          ),
        ],
      ),
    );
  }
}
