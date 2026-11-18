// Demo users, vitals and chat for the mock backend.

import 'dart:math';

import '../../features/auth/data/models/user_model.dart';
import '../../features/medical_chat/data/models/chat_message_model.dart';
import '../../features/vitals_monitor/data/models/patient_summary.dart';
import '../../features/vitals_monitor/data/models/vitals_model.dart';
import '../../features/vitals_monitor/domain/latch.dart';
import '../../features/vitals_monitor/domain/trend.dart';
import '../../features/vitals_monitor/domain/triage.dart';

const kDoctorId = 'b3f1c2e4-5d6a-4b7c-8e9f-0a1b2c3d4e5f';
const kNurseId = 'c4a2d3f5-6e7b-4c8d-9f0a-1b2c3d4e5f60';
const kJohnId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
const kJaneId = '2f1a8b3c-9d4e-4f5a-8b6c-7d8e9f0a1b2c';
const kBobId = '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d';

const mockDoctor = UserModel(
  id: kDoctorId,
  email: 'dr.sarah@medvitals.com',
  name: 'Dr. Sarah Mitchell',
  role: UserRole.doctor,
  specialization: 'Cardiology',
);

const mockNurse = UserModel(
  id: kNurseId,
  email: 'grace.wanjiru@medvitals.com',
  name: 'Nurse Grace Wanjiru',
  role: UserRole.nurse,
  specialization: 'Cardiac triage',
);

const mockPatient = UserModel(
  id: kJohnId,
  email: 'john.doe@example.com',
  name: 'John Doe',
  role: UserRole.patient,
);

const mockUsers = <UserModel>[
  mockDoctor,
  mockNurse,
  mockPatient,
  UserModel(
      id: kJaneId,
      email: 'jane.smith@example.com',
      name: 'Jane Smith',
      role: UserRole.patient),
  UserModel(
      id: kBobId,
      email: 'bob.wilson@example.com',
      name: 'Bob Wilson',
      role: UserRole.patient),
];

/// Patients monitored by the care team.
final mockPatients = [
  for (final u in mockUsers)
    if (u.role == UserRole.patient)
      PatientSummary(id: u.id, name: u.name, email: u.email),
];

const mockVitalsInterval = Duration(seconds: 5);

class _VitalsProfile {
  const _VitalsProfile(this.heartRate, this.spo2, this.systolic, this.diastolic,
      {this.episodes = false, this.deteriorates = false});

  final double heartRate;
  final double spo2;
  final double systolic;
  final double diastolic;

  /// An acute episode every 4 minutes (the simulator's "acute_events"):
  /// tachycardia with desaturation that builds, holds and eases.
  final bool episodes;

  /// A slow 10-minute decline into critical, then 2 minutes of recovery
  /// (the simulator's "deteriorating" scenario).
  final bool deteriorates;
}

const _profiles = <String, _VitalsProfile>{
  kJohnId: _VitalsProfile(72, 97.5, 120, 80),
  kJaneId: _VitalsProfile(78, 97.2, 124, 78, deteriorates: true),
  kBobId: _VitalsProfile(92, 95, 138, 88, episodes: true),
};

/// 0..1 intensity of an acute episode, [t] seconds into a 4-minute cycle.
double _episode(double t) {
  if (t < 90 || t >= 195) return 0;
  if (t < 120) return (t - 90) / 30;
  if (t < 165) return 1;
  return (195 - t) / 30;
}

/// The raw values a wearable reports for one slot (no triage yet).
({double hr, double spo2, double sys, double dia}) _rawValues(
    String patientId, int slot) {
  final rng = Random(Object.hash(patientId, slot));
  final p = _profiles[patientId] ?? const _VitalsProfile(75, 97, 120, 80);
  final seconds = slot * mockVitalsInterval.inSeconds;

  var decline = 0.0; // 0 = baseline, 1 = bottom of the decline
  if (p.deteriorates) {
    final inCycle = seconds % 720;
    decline = inCycle <= 600 ? inCycle / 600 : 0;
  }
  final episode = p.episodes ? _episode((seconds % 240).toDouble()) : 0.0;

  final hr =
      p.heartRate + 56 * decline + 53 * episode + rng.nextDouble() * 6 - 3;
  final spo2 = (p.spo2 - 9 * decline - 9 * episode + rng.nextDouble() - 0.5)
      .clamp(80, 100)
      .toDouble();
  final sys = p.systolic - 32 * decline + rng.nextInt(9) - 4;
  final dia = p.diastolic - 18 * decline + rng.nextInt(5) - 2;
  return (hr: hr, spo2: spo2, sys: sys, dia: dia);
}

/// The reading a patient's wearable reports for the slot containing [time],
/// triaged the way the Telemetry Engine does it: thresholds, trends over the
/// last 5 minutes, then alarm latching. The mock is deterministic per slot,
/// so the history all of that needs is simply regenerated. [stampAt]
/// overrides the timestamp.
VitalsSnapshot mockReading(String patientId, DateTime time,
    {DateTime? stampAt}) {
  final ms = mockVitalsInterval.inMilliseconds;
  final slot = time.millisecondsSinceEpoch ~/ ms;
  final trendSlots = TrendRules.window.inMilliseconds ~/ ms;
  // Two step-downs of a minute each: three minutes of replay settle the latch.
  final latchSlots = latchHold.inMilliseconds * 3 ~/ ms;

  final first = slot - latchSlots - trendSlots;
  final raw = [for (var s = first; s <= slot; s++) _rawValues(patientId, s)];
  DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * ms);

  ({Severity severity, List<String> alerts}) triaged(int s) {
    final i = s - first;
    final v = raw[i];
    final trends = detectTrends([
      for (var k = i - trendSlots; k <= i; k++)
        (
          at: at(first + k),
          heartRate: raw[k].hr,
          spo2: raw[k].spo2,
          systolic: raw[k].sys
        ),
    ]);
    final t = evaluateVitals(heartRate: v.hr, spo2: v.spo2, systolicBP: v.sys);
    return (
      severity:
          trends.isNotEmpty ? t.severity.max(Severity.warning) : t.severity,
      alerts: [...t.alerts, for (final tr in trends) tr.alert],
    );
  }

  final latch = StatusLatch();
  var shown = Severity.stable;
  var held = false;
  late List<String> alerts;
  for (var s = slot - latchSlots; s <= slot; s++) {
    final r = triaged(s);
    (shown, held) = latch.update(at(s), r.severity);
    alerts = r.alerts;
  }

  final v = raw.last;
  return VitalsSnapshot(
    patientId: patientId,
    heartRate: v.hr,
    spo2: v.spo2,
    systolicBP: v.sys,
    diastolicBP: v.dia,
    timestamp: stampAt ?? at(slot),
    severity: shown,
    alerts: [...alerts, if (held) latchHoldAlert],
  );
}

/// The [count] readings *before* the current slot, oldest first.
List<VitalsSnapshot> generateMockVitals(String patientId, {int count = 60}) {
  final now = DateTime.now();
  return List.generate(count, (i) {
    return mockReading(
        patientId, now.subtract(mockVitalsInterval * (count - i)));
  });
}

/// Conversations between [mockDoctor] and each patient.
const mockConversations = <({String id, String doctorId, String patientId})>[
  (id: 'conv-001', doctorId: kDoctorId, patientId: kJohnId),
  (id: 'conv-002', doctorId: kDoctorId, patientId: kJaneId),
  (id: 'conv-003', doctorId: kDoctorId, patientId: kBobId),
];

/// Seed messages per conversation.
Map<String, List<ChatMessage>> buildMockMessages() {
  final now = DateTime.now();
  return {
    'conv-001': [
      ChatMessage(
        id: 'msg-001',
        senderId: kDoctorId,
        content: 'Good morning John. How are you feeling today?',
        timestamp: now.subtract(const Duration(hours: 2)),
        status: MessageStatus.delivered,
      ),
      ChatMessage(
        id: 'msg-002',
        senderId: kJohnId,
        content: "Hi Dr. Mitchell. I'm feeling good, vitals have been stable.",
        timestamp: now.subtract(const Duration(hours: 1, minutes: 55)),
        status: MessageStatus.delivered,
      ),
      ChatMessage(
        id: 'msg-003',
        senderId: kDoctorId,
        content:
            'Excellent. Keep monitoring your heart rate. Aim for 60-80 bpm at rest.',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 50)),
        status: MessageStatus.delivered,
      ),
      ChatMessage(
        id: 'msg-004',
        senderId: kJohnId,
        content: "Understood. I'll keep the wearable on.",
        timestamp: now.subtract(const Duration(hours: 1, minutes: 45)),
        status: MessageStatus.delivered,
      ),
    ],
    'conv-002': [
      ChatMessage(
        id: 'msg-101',
        senderId: kJaneId,
        content:
            'Is it normal for my blood pressure to be higher in the morning?',
        timestamp: now.subtract(const Duration(days: 1, hours: 3)),
        status: MessageStatus.delivered,
      ),
    ],
    'conv-003': [],
  };
}

const mockAutoReplies = [
  'Thanks, noted.',
  'Understood. I\'ll keep an eye on it.',
  'All vitals looking good on my end.',
  'See you at the next appointment.',
];
