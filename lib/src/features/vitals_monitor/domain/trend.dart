// Trend-based deterioration alerts (early warning).
//
// The Telemetry Engine is the source of truth: it adds these alerts to every
// reading it broadcasts. The same rules live here so the mock backend behaves
// identically. Keep in sync with services/telemetry-engine/app/trends.py.
//
// A least-squares line through each vital over the last 5 minutes; the drift
// is that line's change across the window, so one noisy reading can't
// trigger it. One worrying trend raises a reading to at least "warning"; two
// or more together are an early warning that opens a case for the nurse.

import 'dart:math' as math;

abstract final class TrendRules {
  static const window = Duration(minutes: 5);
  static const minSpanSeconds = 120.0;
  static const minReadings = 20;

  static const hrRise = 15.0; // bpm across the window
  static const spo2Drop = 3.0; // percentage points
  static const systolicDrop = 20.0; // mmHg

  /// Alerts from trends start with this, so they can be told apart.
  static const prefix = 'Trend: ';
}

/// One reading reduced to what trend detection needs.
typedef TrendSample = ({
  DateTime at,
  double heartRate,
  double spo2,
  double systolic
});

enum TrendVital { heartRate, spo2, systolic }

class Trend {
  const Trend(this.vital, this.change, this.minutes);

  final TrendVital vital;

  /// Across the window, in the vital's unit (negative = falling).
  final double change;
  final double minutes;

  String get alert {
    final m = math.max(1, (minutes + 0.5).floor());
    final c = (change.abs() + 0.5).floor();
    return switch (vital) {
      TrendVital.heartRate =>
        '${TrendRules.prefix}heart rate rising (+$c bpm over $m min)',
      TrendVital.spo2 =>
        '${TrendRules.prefix}oxygen saturation falling (-$c% over $m min)',
      TrendVital.systolic =>
        '${TrendRules.prefix}blood pressure falling (-$c systolic over $m min)',
    };
  }
}

double _slopePerSecond(List<double> t, List<double> v) {
  final n = t.length;
  final meanT = t.reduce((a, b) => a + b) / n;
  final meanV = v.reduce((a, b) => a + b) / n;
  var cov = 0.0, varT = 0.0;
  for (var i = 0; i < n; i++) {
    cov += (t[i] - meanT) * (v[i] - meanV);
    varT += (t[i] - meanT) * (t[i] - meanT);
  }
  return varT == 0 ? 0 : cov / varT;
}

/// Worrying trends in [samples] (oldest first, already limited to the window).
List<Trend> detectTrends(List<TrendSample> samples) {
  if (samples.length < TrendRules.minReadings) return const [];
  final origin = samples.first.at;
  final t = [
    for (final s in samples) s.at.difference(origin).inMilliseconds / 1000
  ];
  final span = t.last;
  if (span < TrendRules.minSpanSeconds) return const [];

  final trends = <Trend>[];
  void check(TrendVital vital, List<double> values, double threshold,
      {required bool rising}) {
    final change = _slopePerSecond(t, values) * span;
    if (rising ? change >= threshold : change <= -threshold) {
      trends.add(Trend(vital, change, span / 60));
    }
  }

  check(TrendVital.heartRate, [for (final s in samples) s.heartRate],
      TrendRules.hrRise,
      rising: true);
  check(TrendVital.spo2, [for (final s in samples) s.spo2], TrendRules.spo2Drop,
      rising: false);
  check(TrendVital.systolic, [for (final s in samples) s.systolic],
      TrendRules.systolicDrop,
      rising: false);
  return trends;
}

/// How many of a reading's alerts are trends (two or more = early warning).
int trendAlertCount(List<String> alerts) =>
    alerts.where((a) => a.startsWith(TrendRules.prefix)).length;
