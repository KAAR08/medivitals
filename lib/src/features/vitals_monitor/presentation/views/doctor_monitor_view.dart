import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/initials.dart';
import '../../data/models/vitals_model.dart';
import '../../domain/triage.dart';
import '../viewmodels/vitals_viewmodel.dart';
import '../widgets/health_banner.dart';

class DoctorMonitorView extends ConsumerWidget {
  const DoctorMonitorView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(doctorMonitorViewModelProvider);
    final patients = monitorState.sortedPatients;
    final anomalyCount = monitorState.criticalCount;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Patients'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryBar(
            activeCount: patients.where((p) => p.isConnected).length,
            anomalyCount: anomalyCount,
            isConnected: monitorState.isConnected,
          ),
          Expanded(
            child: patients.isEmpty
                ? const _EmptyState()
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.05,
                    ),
                    itemCount: patients.length,
                    itemBuilder: (_, i) => _PatientCard(
                      patientState: patients[i],
                      onTap: () => context.push(
                          AppRoutes.patientDetailPath(patients[i].patientId)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnomalyBadge extends StatelessWidget {
  const _AnomalyBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.criticalLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: c.critical),
          const SizedBox(width: 5),
          Text(
            '$count critical',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.critical,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.activeCount,
    required this.anomalyCount,
    required this.isConnected,
  });

  final int activeCount;
  final int anomalyCount;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? c.success : c.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isConnected
                ? 'Live · $activeCount patients'
                : 'Connecting to stream…',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          if (anomalyCount > 0) _AnomalyBadge(count: anomalyCount),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors_off_outlined, size: 48, color: c.textTertiary),
          const SizedBox(height: 12),
          Text(
            'No patients connected',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Waiting for incoming telemetry…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PatientCard extends StatefulWidget {
  const _PatientCard({required this.patientState, required this.onTap});
  final PatientVitalsState patientState;
  final VoidCallback onTap;

  @override
  State<_PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<_PatientCard>
    with SingleTickerProviderStateMixin {
  static bool _isCritical(PatientVitalsState p) =>
      p.severity == Severity.critical;

  late final AnimationController _flash;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _opacity = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _flash, curve: Curves.easeInOut),
    );
    if (_isCritical(widget.patientState)) _flash.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PatientCard old) {
    super.didUpdateWidget(old);
    final changed =
        _isCritical(widget.patientState) != _isCritical(old.patientState);
    if (!changed) return;
    if (_isCritical(widget.patientState)) {
      _flash.repeat(reverse: true);
    } else {
      _flash
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final severity = widget.patientState.severity;
    final hasAnomaly = severity == Severity.critical;
    final latest = widget.patientState.latest;

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        // Critical patients pulse red; everyone else is a plain card and
        // the severity chip says the rest.
        return Container(
          decoration: context.card(
            color: hasAnomaly
                ? Color.lerp(c.surface, c.criticalLight, _opacity.value)
                : null,
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: hasAnomaly ? c.critical : c.brandLight,
                      child: Text(
                        initials(widget.patientState.patientName),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hasAnomaly ? Colors.white : c.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.patientState.patientName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: hasAnomaly ? c.critical : c.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SeverityChip(severity: severity),
                const Spacer(),
                _MetricRow(
                  label: 'HR',
                  value: latest != null
                      ? '${latest.heartRate.toStringAsFixed(0)} bpm'
                      : '--',
                  isAlert: latest != null &&
                      (latest.heartRate > TriageThresholds.hrWarningHigh ||
                          latest.heartRate < TriageThresholds.hrWarningLow),
                ),
                const SizedBox(height: 8),
                _MetricRow(
                  label: 'SpO₂',
                  value: latest != null
                      ? '${latest.spo2.toStringAsFixed(0)}%'
                      : '--',
                  isAlert: latest != null &&
                      latest.spo2 < TriageThresholds.spo2WarningLow,
                ),
                const SizedBox(height: 8),
                _MetricRow(
                  label: 'BP',
                  value: latest != null
                      ? '${latest.systolicBP.toStringAsFixed(0)}/${latest.diastolicBP.toStringAsFixed(0)}'
                      : '--',
                  isAlert: latest != null &&
                      (latest.systolicBP > TriageThresholds.sysWarningHigh ||
                          latest.systolicBP < TriageThresholds.sysWarningLow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the card's little table: muted label left, value right.
class _MetricRow extends StatelessWidget {
  const _MetricRow(
      {required this.label, required this.value, required this.isAlert});

  final String label;
  final String value;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.textTertiary)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isAlert ? c.critical : c.textPrimary,
          ),
        ),
      ],
    );
  }
}
