import '../../domain/triage.dart';

class VitalsSnapshot {
  const VitalsSnapshot({
    required this.patientId,
    required this.heartRate,
    required this.spo2,
    required this.systolicBP,
    required this.diastolicBP,
    required this.timestamp,
    this.severity = Severity.stable,
    this.alerts = const [],
    this.receivedAt,
  });

  /// Pseudonymized patient UUID — telemetry never carries names.
  final String patientId;
  final double heartRate;
  final double spo2;
  final double systolicBP;
  final double diastolicBP;

  /// When the reading was generated (by the wearable / simulator).
  final DateTime timestamp;

  /// Triage result, tagged by the Telemetry Engine.
  final Severity severity;
  final List<String> alerts;

  /// When this device received it (live readings only; null for history).
  final DateTime? receivedAt;

  /// Sensor to screen (target: under 2 s).
  Duration? get latency => receivedAt?.difference(timestamp);

  /// Parses an engine event. If the engine did not tag it, triage runs here.
  factory VitalsSnapshot.fromJson(Map<String, dynamic> json) {
    final heartRate = (json['heartRate'] as num).toDouble();
    final spo2 = (json['spo2'] as num).toDouble();
    final systolicBP = (json['systolicBP'] as num).toDouble();
    final tagged = json['severity'] as String?;
    final triage = tagged == null
        ? evaluateVitals(
            heartRate: heartRate, spo2: spo2, systolicBP: systolicBP)
        : TriageResult(
            Severity.fromName(tagged),
            (json['alerts'] as List<dynamic>? ?? const []).cast<String>(),
          );
    return VitalsSnapshot(
      patientId: json['patientId'] as String,
      heartRate: heartRate,
      spo2: spo2,
      systolicBP: systolicBP,
      diastolicBP: (json['diastolicBP'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      severity: triage.severity,
      alerts: triage.alerts,
    );
  }

  Map<String, dynamic> toJson() => {
        'patientId': patientId,
        'heartRate': heartRate,
        'spo2': spo2,
        'systolicBP': systolicBP,
        'diastolicBP': diastolicBP,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'severity': severity.name,
        'alerts': alerts,
      };

  VitalsSnapshot copyWith({DateTime? receivedAt}) {
    return VitalsSnapshot(
      patientId: patientId,
      heartRate: heartRate,
      spo2: spo2,
      systolicBP: systolicBP,
      diastolicBP: diastolicBP,
      timestamp: timestamp,
      severity: severity,
      alerts: alerts,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }
}

class PatientVitalsState {
  const PatientVitalsState({
    required this.patientId,
    required this.patientName,
    this.history = const [],
    this.latest,
    this.isConnected = false,
    this.errorMessage,
  });

  final String patientId;
  final String patientName;
  final List<VitalsSnapshot> history;
  final VitalsSnapshot? latest;
  final bool isConnected;

  /// Set when the history could not be loaded; cleared on the next success.
  final String? errorMessage;

  /// Current triage level — drives the green/amber/red health banner.
  Severity get severity => latest?.severity ?? Severity.stable;

  /// Latency of the most recent live reading, if any.
  Duration? get latency => latest?.latency;

  PatientVitalsState copyWith({
    String? patientName,
    List<VitalsSnapshot>? history,
    VitalsSnapshot? latest,
    bool? isConnected,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PatientVitalsState(
      patientId: patientId,
      patientName: patientName ?? this.patientName,
      history: history ?? this.history,
      latest: latest ?? this.latest,
      isConnected: isConnected ?? this.isConnected,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class DoctorMonitorState {
  const DoctorMonitorState({
    this.patients = const {},
    this.isConnected = false,
  });

  final Map<String, PatientVitalsState> patients;
  final bool isConnected;

  int get criticalCount =>
      patients.values.where((p) => p.severity == Severity.critical).length;

  int get warningCount =>
      patients.values.where((p) => p.severity == Severity.warning).length;

  /// Most severe first, then alphabetical — the triage order.
  List<PatientVitalsState> get sortedPatients {
    return patients.values.toList()
      ..sort((a, b) {
        final bySeverity = b.severity.index.compareTo(a.severity.index);
        return bySeverity != 0
            ? bySeverity
            : a.patientName.compareTo(b.patientName);
      });
  }

  DoctorMonitorState copyWith({
    Map<String, PatientVitalsState>? patients,
    bool? isConnected,
  }) {
    return DoctorMonitorState(
      patients: patients ?? this.patients,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}
