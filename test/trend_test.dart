import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:medivitallink/src/data/services/mock_data.dart';
import 'package:medivitallink/src/features/vitals_monitor/domain/trend.dart';
import 'package:medivitallink/src/features/vitals_monitor/domain/triage.dart';

/// Readings every 5 s drifting linearly from start to end values.
List<TrendSample> series(
  double minutes, {
  int everySeconds = 5,
  (double, double) hr = (75, 75),
  (double, double) spo2 = (97, 97),
  (double, double) sys = (122, 122),
  double noise = 0,
}) {
  final rng = Random(7);
  final n = (minutes * 60 / everySeconds).floor() + 1;
  final start = DateTime.utc(2026);
  double at((double, double) v, double f) =>
      v.$1 + (v.$2 - v.$1) * f + (rng.nextDouble() * 2 - 1) * noise;
  return [
    for (var i = 0; i < n; i++)
      (
        at: start.add(Duration(seconds: i * everySeconds)),
        heartRate: at(hr, i / (n - 1)),
        spo2: at(spo2, i / (n - 1)),
        systolic: at(sys, i / (n - 1)),
      ),
  ];
}

void main() {
  test('steady, noisy vitals raise nothing', () {
    expect(detectTrends(series(5, hr: (76, 76), noise: 4)), isEmpty);
  });

  test(
      'each worrying direction is detected, with the same wording as the engine',
      () {
    final trends =
        detectTrends(series(4, hr: (76, 96), spo2: (97, 93), sys: (124, 100)));
    expect(trends.map((t) => t.alert), [
      'Trend: heart rate rising (+20 bpm over 4 min)',
      'Trend: oxygen saturation falling (-4% over 4 min)',
      'Trend: blood pressure falling (-24 systolic over 4 min)',
    ]);
  });

  test('recovery is not flagged', () {
    expect(
        detectTrends(series(4, hr: (100, 78), spo2: (93, 97), sys: (100, 124))),
        isEmpty);
  });

  test('needs at least 2 minutes and enough readings', () {
    expect(detectTrends(series(1, hr: (70, 110))), isEmpty);
    expect(detectTrends(series(3, everySeconds: 20, hr: (70, 110))), isEmpty);
  });

  group('demo data', () {
    final start = DateTime(2026, 11, 19, 9);
    List<({Duration t, Severity severity, int trends})> run(
            String patientId, Duration length) =>
        [
          for (var t = Duration.zero; t < length; t += mockVitalsInterval)
            (() {
              final r = mockReading(patientId, start.add(t));
              return (
                t: t,
                severity: r.severity,
                trends: trendAlertCount(r.alerts)
              );
            })(),
        ];

    test("Jane's slow decline: the early warning comes minutes before critical",
        () {
      final readings =
          run(kJaneId, const Duration(minutes: 24)); // two full cycles
      for (var i = 0; i < readings.length; i++) {
        final r = readings[i];
        if (r.severity != Severity.critical) continue;
        // Walk back to the start of this decline and find the early warning.
        final before = readings.sublist(max(0, i - 120), i);
        final warning = before.where((x) => x.trends >= 2).firstOrNull;
        expect(warning, isNotNull,
            reason: 'no early warning before critical at ${r.t}');
        expect(
            r.t - warning!.t, greaterThanOrEqualTo(const Duration(minutes: 2)));
        return;
      }
      fail('Jane never became critical');
    });

    test('a stable patient never shows a trend', () {
      expect(run(kJohnId, const Duration(hours: 1)).where((r) => r.trends > 0),
          isEmpty);
    });
  });
}
