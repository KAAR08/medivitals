import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medivitallink/src/data/services/mock_data.dart';
import 'package:medivitallink/src/features/alarm/alarm_controller.dart';
import 'package:medivitallink/src/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:medivitallink/src/features/vitals_monitor/data/models/vitals_model.dart';
import 'package:medivitallink/src/features/vitals_monitor/domain/triage.dart';
import 'package:medivitallink/src/features/vitals_monitor/presentation/viewmodels/vitals_viewmodel.dart';

class SilentPlayer implements AlarmPlayer {
  bool playing = false;
  @override
  Future<void> start() async => playing = true;
  @override
  Future<void> stop() async => playing = false;
}

/// A ward whose patients' status the test sets directly.
class FakeWard extends DoctorMonitorViewModel {
  @override
  DoctorMonitorState build() => const DoctorMonitorState();

  void set(Map<String, Severity> severities) {
    state = DoctorMonitorState(patients: {
      for (final MapEntry(key: id, value: sev) in severities.entries)
        id: PatientVitalsState(
          patientId: id,
          patientName: id == kBobId ? 'Bob Wilson' : 'Jane Smith',
          latest: VitalsSnapshot(
            patientId: id,
            heartRate: 70,
            spo2: 97,
            systolicBP: 120,
            diastolicBP: 80,
            timestamp: DateTime.now(),
            severity: sev,
          ),
        ),
    });
  }
}

void main() {
  final now = DateTime(2026, 11, 19, 9);

  group('shouldSound', () {
    bool sound({
      Set<String> critical = const {'bob'},
      Set<String> acknowledged = const {},
      DateTime? silencedUntil,
      bool onCall = false,
    }) =>
        shouldSound(
          critical: critical,
          acknowledged: acknowledged,
          silencedUntil: silencedUntil,
          now: now,
          onCall: onCall,
        );

    test('sounds while anyone is critical', () {
      expect(sound(), isTrue);
      expect(sound(critical: {}), isFalse);
    });

    test('silence holds for the acknowledged patients only', () {
      final until = now.add(const Duration(minutes: 1));
      expect(sound(acknowledged: {'bob'}, silencedUntil: until), isFalse);
      expect(
          sound(
              critical: {'bob', 'jane'},
              acknowledged: {'bob'},
              silencedUntil: until),
          isTrue,
          reason: 'a newly critical patient breaks the silence');
    });

    test('an expired silence sounds again', () {
      expect(
          sound(
              acknowledged: {'bob'},
              silencedUntil: now.subtract(const Duration(seconds: 1))),
          isTrue);
    });

    test('quiet during a call', () {
      expect(sound(onCall: true), isFalse);
    });
  });

  test('the care team hears critical patients and can silence the alarm', () {
    final player = SilentPlayer();
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => mockNurse),
      alarmPlayerProvider.overrideWithValue(player),
      doctorMonitorViewModelProvider.overrideWith(FakeWard.new),
    ]);
    addTearDown(container.dispose);
    container.listen(alarmControllerProvider, (_, __) {});
    final ward =
        container.read(doctorMonitorViewModelProvider.notifier) as FakeWard;

    ward.set({kBobId: Severity.critical, kJaneId: Severity.stable});
    var alarm = container.read(alarmControllerProvider);
    expect(alarm.critical.values, ['Bob Wilson']);
    expect(alarm.sounding, isTrue);
    expect(player.playing, isTrue);

    container.read(alarmControllerProvider.notifier).silence();
    alarm = container.read(alarmControllerProvider);
    expect(player.playing, isFalse);
    expect(alarm.silencedUntil, isNotNull);

    ward.set({kBobId: Severity.critical, kJaneId: Severity.critical});
    expect(player.playing, isTrue, reason: 'Jane is newly critical');

    ward.set({kBobId: Severity.warning, kJaneId: Severity.stable});
    expect(player.playing, isFalse);
    expect(container.read(alarmControllerProvider).active, isFalse);
  });

  test('patients get no siren', () {
    final player = SilentPlayer();
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => mockPatient),
      alarmPlayerProvider.overrideWithValue(player),
    ]);
    addTearDown(container.dispose);
    container.listen(alarmControllerProvider, (_, __) {});
    expect(container.read(alarmControllerProvider).active, isFalse);
    expect(player.playing, isFalse);
  });
}
