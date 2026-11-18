// Threshold triage, mirroring services/telemetry-engine/app/triage.py (keep
// in sync). The engine tags every reading; these rules serve the mock backend
// and any reading that arrives untagged.

enum Severity {
  stable,
  warning,
  critical;

  /// Parses the engine's lowercase name; unknown values are treated as stable.
  static Severity fromName(String? name) =>
      Severity.values.where((s) => s.name == name).firstOrNull ??
      Severity.stable;

  Severity max(Severity other) => index >= other.index ? this : other;
}

/// The outcome of evaluating one reading: overall severity plus the reasons.
class TriageResult {
  const TriageResult(this.severity, this.alerts);

  final Severity severity;

  /// Human-readable reasons, most severe first, e.g. "Heart rate high (142 bpm)".
  final List<String> alerts;

  static const stable = TriageResult(Severity.stable, []);
}

/// Thresholds for adult post-cardiac-surgery monitoring. Inclusive bounds
/// are "normal"; crossing a warning bound asks for attention, crossing a
/// critical bound means action is required now.
abstract final class TriageThresholds {
  static const hrCriticalLow = 40.0;
  static const hrWarningLow = 50.0;
  static const hrWarningHigh = 110.0;
  static const hrCriticalHigh = 130.0;

  static const spo2CriticalLow = 90.0;
  static const spo2WarningLow = 94.0;

  static const sysCriticalLow = 90.0;
  static const sysWarningLow = 100.0;
  static const sysWarningHigh = 160.0;
  static const sysCriticalHigh = 180.0;
}

TriageResult evaluateVitals({
  required double heartRate,
  required double spo2,
  required double systolicBP,
}) {
  final critical = <String>[];
  final warning = <String>[];

  final hr = heartRate.round();
  if (heartRate > TriageThresholds.hrCriticalHigh) {
    critical.add('Heart rate very high ($hr bpm)');
  } else if (heartRate < TriageThresholds.hrCriticalLow) {
    critical.add('Heart rate very low ($hr bpm)');
  } else if (heartRate > TriageThresholds.hrWarningHigh) {
    warning.add('Heart rate elevated ($hr bpm)');
  } else if (heartRate < TriageThresholds.hrWarningLow) {
    warning.add('Heart rate low ($hr bpm)');
  }

  final o2 = spo2.round();
  if (spo2 < TriageThresholds.spo2CriticalLow) {
    critical.add('Oxygen saturation critical ($o2%)');
  } else if (spo2 < TriageThresholds.spo2WarningLow) {
    warning.add('Oxygen saturation low ($o2%)');
  }

  final sys = systolicBP.round();
  if (systolicBP > TriageThresholds.sysCriticalHigh) {
    critical.add('Blood pressure very high ($sys systolic)');
  } else if (systolicBP < TriageThresholds.sysCriticalLow) {
    critical.add('Blood pressure very low ($sys systolic)');
  } else if (systolicBP > TriageThresholds.sysWarningHigh) {
    warning.add('Blood pressure elevated ($sys systolic)');
  } else if (systolicBP < TriageThresholds.sysWarningLow) {
    warning.add('Blood pressure low ($sys systolic)');
  }

  final severity = critical.isNotEmpty
      ? Severity.critical
      : warning.isNotEmpty
          ? Severity.warning
          : Severity.stable;
  return TriageResult(severity, [...critical, ...warning]);
}
