import '../../../vitals_monitor/domain/triage.dart';

/// Lifecycle of a case: the triage nurse takes it (acknowledged) and calls
/// the patient, then resolves it, refers it to a doctor, or dispatches an
/// ambulance (simulated: nothing real is dispatched).
enum EscalationStatus {
  pending,
  acknowledged,
  referred,
  ambulance,
  resolved;

  static EscalationStatus fromName(String? name) =>
      EscalationStatus.values.where((s) => s.name == name).firstOrNull ??
      EscalationStatus.pending;

  bool get isOpen => this != EscalationStatus.resolved;

  /// Where a case can go next (mirrors the Telemetry Engine's rules).
  Set<EscalationStatus> get next => switch (this) {
        pending => {acknowledged, referred, ambulance, resolved},
        acknowledged => {referred, ambulance, resolved},
        referred => {acknowledged, ambulance, resolved},
        ambulance => {resolved},
        resolved => const {},
      };
}

/// One step in a case's history: raised, taken, referred, a call, ...
class EscalationEvent {
  const EscalationEvent({
    required this.at,
    required this.action,
    required this.role,
    this.by,
    this.note,
    this.callOutcome,
    this.callSeconds,
    this.video = false,
  });

  final DateTime at;

  /// raised | acknowledged | referred | ambulance | resolved | call
  final String action;
  final String role;
  final String? by;
  final String? note;

  /// For calls: answered | missed | declined | cancelled.
  final String? callOutcome;
  final int? callSeconds;
  final bool video;

  factory EscalationEvent.fromJson(Map<String, dynamic> json) =>
      EscalationEvent(
        at: DateTime.parse(json['at'] as String),
        action: json['action'] as String,
        role: json['role'] as String? ?? '',
        by: json['by'] as String?,
        note: json['note'] as String?,
        callOutcome: json['outcome'] as String?,
        callSeconds: (json['seconds'] as num?)?.toInt(),
        video: json['video'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'action': action,
        'role': role,
        if (by != null) 'by': by,
        if (note != null) 'note': note,
        if (callOutcome != null) 'outcome': callOutcome,
        if (callSeconds != null) 'seconds': callSeconds,
        if (action == 'call') 'video': video,
      };
}

/// Who raised it: the patient or their caregiver tapped the button, or the
/// Telemetry Engine raised it automatically on a critical reading.
enum EscalationSource {
  patient,
  caregiver,
  auto;

  static EscalationSource fromName(String? name) =>
      EscalationSource.values.where((s) => s.name == name).firstOrNull ??
      EscalationSource.patient;
}

/// A case for the triage nurse: a callback request or an automatic alert.
/// Carries only the pseudonymized patient ID.
class Escalation {
  const Escalation({
    required this.id,
    required this.patientId,
    required this.source,
    required this.status,
    required this.createdAt,
    this.severity = Severity.stable,
    this.alerts = const [],
    this.note,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.resolvedAt,
    this.timeline = const [],
  });

  final String id;
  final String patientId;
  final EscalationSource source;
  final EscalationStatus status;
  final DateTime createdAt;

  /// The patient's triage level when the request was raised.
  final Severity severity;
  final List<String> alerts;
  final String? note;

  /// ID of the nurse who picked it up.
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;

  /// What happened, oldest first.
  final List<EscalationEvent> timeline;

  /// The latest clinician decision note (referral reason, outcome, ...).
  String? get outcomeNote {
    for (final e in timeline.reversed) {
      if (e.action != 'call' && e.action != 'raised' && e.note != null) {
        return e.note;
      }
    }
    return null;
  }

  factory Escalation.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) {
      final v = json[key] as String?;
      return v == null ? null : DateTime.parse(v);
    }

    return Escalation(
      id: json['id'] as String,
      patientId: json['patientId'] as String,
      source: EscalationSource.fromName(json['source'] as String?),
      status: EscalationStatus.fromName(json['status'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      severity: Severity.fromName(json['severity'] as String?),
      alerts: (json['alerts'] as List<dynamic>? ?? const []).cast<String>(),
      note: json['note'] as String?,
      acknowledgedBy: json['acknowledgedBy'] as String?,
      acknowledgedAt: time('acknowledgedAt'),
      resolvedAt: time('resolvedAt'),
      timeline: [
        for (final e in json['timeline'] as List<dynamic>? ?? const [])
          EscalationEvent.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'source': source.name,
        'status': status.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'severity': severity.name,
        'alerts': alerts,
        if (note != null) 'note': note,
        if (acknowledgedBy != null) 'acknowledgedBy': acknowledgedBy,
        if (acknowledgedAt != null)
          'acknowledgedAt': acknowledgedAt!.toUtc().toIso8601String(),
        if (resolvedAt != null)
          'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
        'timeline': [for (final e in timeline) e.toJson()],
      };

  Escalation copyWith({
    EscalationStatus? status,
    String? acknowledgedBy,
    DateTime? acknowledgedAt,
    DateTime? resolvedAt,
    List<EscalationEvent>? timeline,
  }) {
    return Escalation(
      id: id,
      patientId: patientId,
      source: source,
      status: status ?? this.status,
      createdAt: createdAt,
      severity: severity,
      alerts: alerts,
      note: note,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      timeline: timeline ?? this.timeline,
    );
  }
}
