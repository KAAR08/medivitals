import 'package:flutter_test/flutter_test.dart';
import 'package:medivitallink/src/features/vitals_monitor/data/models/vitals_model.dart';
import 'package:medivitallink/src/features/vitals_monitor/domain/triage.dart';

TriageResult triage({double hr = 75, double spo2 = 97, double sys = 120}) =>
    evaluateVitals(heartRate: hr, spo2: spo2, systolicBP: sys);

void main() {
  test('normal post-op vitals are stable with no alerts', () {
    final r = triage();
    expect(r.severity, Severity.stable);
    expect(r.alerts, isEmpty);
  });

  group('boundaries are inclusive of the normal range', () {
    test('heart rate', () {
      expect(triage(hr: 110).severity, Severity.stable);
      expect(triage(hr: 111).severity, Severity.warning);
      expect(triage(hr: 130).severity, Severity.warning);
      expect(triage(hr: 131).severity, Severity.critical);
      expect(triage(hr: 50).severity, Severity.stable);
      expect(triage(hr: 49).severity, Severity.warning);
      expect(triage(hr: 39).severity, Severity.critical);
    });

    test('oxygen saturation', () {
      expect(triage(spo2: 94).severity, Severity.stable);
      expect(triage(spo2: 93.5).severity, Severity.warning);
      expect(triage(spo2: 90).severity, Severity.warning);
      expect(triage(spo2: 89.9).severity, Severity.critical);
    });

    test('systolic blood pressure', () {
      expect(triage(sys: 160).severity, Severity.stable);
      expect(triage(sys: 161).severity, Severity.warning);
      expect(triage(sys: 181).severity, Severity.critical);
      expect(triage(sys: 99).severity, Severity.warning);
      expect(triage(sys: 89).severity, Severity.critical);
    });
  });

  test('overall severity is the worst signal, critical reasons listed first',
      () {
    final r = triage(hr: 115, spo2: 88);
    expect(r.severity, Severity.critical);
    expect(r.alerts.first, contains('Oxygen saturation critical'));
    expect(r.alerts.last, contains('Heart rate elevated'));
  });

  group('VitalsSnapshot.fromJson', () {
    final base = {
      'patientId': '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      'heartRate': 142,
      'spo2': 97,
      'systolicBP': 120,
      'diastolicBP': 80,
      'timestamp': '2026-10-28T10:00:00Z',
    };

    test('trusts the engine\'s severity tag when present', () {
      final s = VitalsSnapshot.fromJson({
        ...base,
        'severity': 'warning',
        'alerts': ['from engine'],
      });
      expect(s.severity, Severity.warning);
      expect(s.alerts, ['from engine']);
    });

    test('triages locally when the reading arrives untagged', () {
      final s = VitalsSnapshot.fromJson(base);
      expect(s.severity, Severity.critical);
    });

    test('latency is measured from generation to receipt', () {
      final s = VitalsSnapshot.fromJson(base)
          .copyWith(receivedAt: DateTime.parse('2026-10-28T10:00:00.350Z'));
      expect(s.latency, const Duration(milliseconds: 350));
    });
  });
}
