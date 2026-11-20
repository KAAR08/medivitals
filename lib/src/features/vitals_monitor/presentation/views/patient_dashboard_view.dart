import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../../escalation/presentation/views/callback_request_card.dart';
import '../../../calls/presentation/viewmodels/call_controller.dart';
import '../../../escalation/presentation/viewmodels/escalation_viewmodel.dart';
import '../../../medical_chat/presentation/viewmodels/chat_viewmodel.dart';
import '../../data/models/vitals_model.dart';
import '../../data/repositories/vitals_repository.dart';
import '../../domain/triage.dart';
import '../viewmodels/vitals_viewmodel.dart';
import '../widgets/health_banner.dart';
import '../../../../core/layout/responsive.dart';

/// Live vitals for one patient: the signed-in patient (`patientId` null), or
/// the patient at `/patients/:id` for the care team.
class PatientDashboardView extends ConsumerWidget {
  const PatientDashboardView({super.key, this.patientId});

  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownId = ref.watch(currentUserProvider)?.id;
    final id = patientId ?? ownId;
    // Briefly null while signing out, before the router leaves this screen.
    if (id == null) return const Scaffold();

    final isOwnDashboard = patientId == null;
    final c = context.colors;
    final vitals = ref.watch(vitalsViewModelProvider(id));
    final latest = vitals.latest;
    final dateStr = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isOwnDashboard ? 'MedVitals Link' : _patientName(ref, id)),
            Text(dateStr, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        actions: [
          _LiveIndicator(
              isConnected: vitals.isConnected, latency: vitals.latency),
          if (!isOwnDashboard) ...[
            _CallPatientButton(
                patientId: id, patientName: _patientName(ref, id)),
            if (AppConfig.chatEnabled) _MessagePatientButton(patientId: id),
          ],
        ],
      ),
      body: ReadableWidth(
          child: RefreshIndicator(
        color: c.brand,
        onRefresh: () =>
            ref.read(vitalsViewModelProvider(id).notifier).refresh(),
        child: CustomScrollView(
          // Always scrollable so pull-to-refresh works even when content is short.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (vitals.errorMessage != null) ...[
                    _ErrorBanner(message: vitals.errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  if (!vitals.isConnected) ...[
                    _NoLiveDataBanner(lastReading: latest?.timestamp),
                    const SizedBox(height: 12),
                  ],
                  HealthBanner(
                      severity: vitals.severity,
                      alerts: latest?.alerts ?? const []),
                  if (isOwnDashboard) ...[
                    const SizedBox(height: 12),
                    CallbackRequestCard(patientId: id),
                  ],
                  const SizedBox(height: 20),
                  const _SectionLabel(label: 'Live Metrics'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _VitalTile(
                          label: 'Heart Rate',
                          value: latest != null
                              ? latest.heartRate.toStringAsFixed(0)
                              : '--',
                          unit: 'bpm',
                          icon: Icons.favorite_border_rounded,
                          color: c.chartHR,
                          isAnomaly: latest != null &&
                              (latest.heartRate >
                                      TriageThresholds.hrWarningHigh ||
                                  latest.heartRate <
                                      TriageThresholds.hrWarningLow),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _VitalTile(
                          label: 'SpO₂',
                          value: latest != null
                              ? latest.spo2.toStringAsFixed(0)
                              : '--',
                          unit: '%',
                          icon: Icons.water_drop_outlined,
                          color: c.chartSpO2,
                          isAnomaly: latest != null &&
                              latest.spo2 < TriageThresholds.spo2WarningLow,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _VitalTile(
                    label: 'Blood Pressure',
                    value: latest != null
                        ? '${latest.systolicBP.toStringAsFixed(0)}/${latest.diastolicBP.toStringAsFixed(0)}'
                        : '--/--',
                    unit: 'mmHg',
                    icon: Icons.show_chart_rounded,
                    color: c.chartBP,
                    isAnomaly: latest != null &&
                        (latest.systolicBP > TriageThresholds.sysWarningHigh ||
                            latest.systolicBP < TriageThresholds.sysWarningLow),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel(label: 'Heart Rate Trend'),
                  const SizedBox(height: 10),
                  _ChartCard(
                    history: vitals.history,
                    color: c.chartHR,
                    getValue: (s) => s.heartRate,
                    minY: 40,
                    maxY: 180,
                    label: 'bpm',
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel(label: 'SpO₂ Trend'),
                  const SizedBox(height: 10),
                  _ChartCard(
                    history: vitals.history,
                    color: c.chartSpO2,
                    getValue: (s) => s.spo2,
                    minY: 80,
                    maxY: 100,
                    label: '%',
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      )),
    );
  }

  String _patientName(WidgetRef ref, String id) {
    final patients =
        ref.watch(monitoredPatientsProvider).valueOrNull ?? const [];
    for (final p in patients) {
      if (p.id == id) return p.name;
    }
    return 'Patient';
  }
}

/// Care team: call the patient (about their open case, if they have one).
class _CallPatientButton extends ConsumerWidget {
  const _CallPatientButton(
      {required this.patientId, required this.patientName});
  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onCall = ref.watch(callControllerProvider)?.isLive ?? false;
    final latest = ref.watch(latestEscalationForProvider(patientId));
    return IconButton(
      tooltip: 'Call patient',
      icon: const Icon(Icons.call_rounded),
      onPressed: onCall
          ? null
          : () => ref.read(callControllerProvider.notifier).callPatient(
                patientId: patientId,
                patientName: patientName,
                escalationId:
                    latest != null && latest.status.isOpen ? latest.id : null,
              ),
    );
  }
}

class _MessagePatientButton extends ConsumerWidget {
  const _MessagePatientButton({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations =
        ref.watch(conversationsProvider).valueOrNull ?? const [];
    final match =
        conversations.where((c) => c.participantId == patientId).firstOrNull;
    return IconButton(
      tooltip: 'Message patient',
      icon: const Icon(Icons.chat_bubble_outline_rounded),
      onPressed: match == null
          ? null
          : () => context.push(AppRoutes.chatDetailPath(match.id)),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.warningLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: c.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message Pull down to retry.',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "● Live 38 ms": the stream is up, and the latest reading's sensor-to-screen
/// time (target: under 2 s).
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.isConnected, this.latency});
  final bool isConnected;
  final Duration? latency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ms = latency?.inMilliseconds;
    final slow = ms != null && ms > 2000;
    final color =
        !isConnected ? c.textTertiary : (slow ? c.warning : c.success);
    return Tooltip(
      message: isConnected
          ? 'Receiving live readings. Delay from sensor to screen: ${ms ?? '–'} ms (target under 2 s)'
          : 'Not receiving live readings',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              isConnected ? 'Live' : 'Offline',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary),
            ),
            if (isConnected && ms != null) ...[
              const SizedBox(width: 4),
              Text('${ms < 0 ? 0 : ms} ms',
                  style: TextStyle(fontSize: 12, color: c.textTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stale vitals must never look current: when the stream stops, say so.
class _NoLiveDataBanner extends StatelessWidget {
  const _NoLiveDataBanner({this.lastReading});
  final DateTime? lastReading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final since = lastReading == null
        ? 'Waiting for the first reading.'
        : 'Last reading at ${DateFormat('HH:mm').format(lastReading!.toLocal())}.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: c.warningLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.sensors_off_rounded, size: 18, color: c.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No live data. $since',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _VitalTile extends StatelessWidget {
  const _VitalTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.isAnomaly,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final bool isAnomaly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelColor = isAnomaly ? c.critical : c.textSecondary;
    final valueColor = isAnomaly ? c.critical : c.textPrimary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.card(color: isAnomaly ? c.criticalLight : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: isAnomaly ? c.critical : color),
                    const SizedBox(width: 5),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            color: labelColor,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: valueColor,
                        height: 1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        unit,
                        style: TextStyle(fontSize: 11, color: c.textTertiary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.history,
    required this.color,
    required this.getValue,
    required this.minY,
    required this.maxY,
    required this.label,
  });

  final List<VitalsSnapshot> history;
  final Color color;
  final double Function(VitalsSnapshot) getValue;
  final double minY;
  final double maxY;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 140,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: context.card(),
      child: history.isEmpty
          ? Center(
              child: Text(
                'Waiting for data…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : LineChart(_buildData(c)),
    );
  }

  LineChartData _buildData(AppColors c) {
    final spots = history.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), getValue(e.value));
    }).toList();

    return LineChartData(
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => c.textPrimary.fade(0.85),
          tooltipRoundedRadius: 6,
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(0)} $label',
                    TextStyle(
                        color: c.surface,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          color: color,
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => spot.x == spots.last.x,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 4,
              color: color,
              strokeWidth: 2,
              strokeColor: c.surface,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.fade(0.15), color.fade(0.0)],
            ),
          ),
        ),
      ],
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: (maxY - minY) / 4,
        getDrawingHorizontalLine: (_) => FlLine(
          color: c.divider,
          strokeWidth: 1,
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              return Text(
                value.toInt().toString(),
                style: TextStyle(fontSize: 10, color: c.textTertiary),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
    );
  }
}
