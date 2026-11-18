import 'package:flutter_test/flutter_test.dart';

import 'package:medivitallink/src/data/services/mock_data.dart';
import 'package:medivitallink/src/features/vitals_monitor/domain/latch.dart';
import 'package:medivitallink/src/features/vitals_monitor/domain/triage.dart';

const s = Severity.stable, w = Severity.warning, c = Severity.critical;
final start = DateTime.utc(2026);

List<Severity> run(List<(int, Severity)> raw) {
  final latch = StatusLatch();
  return [
    for (final (t, sev) in raw)
      latch.update(start.add(Duration(seconds: t)), sev).$1,
  ];
}

void main() {
  test('escalates on the first bad reading', () {
    expect(run([(0, s), (1, c)]), [s, c]);
  });

  test('steps down one level per calm minute (same as the engine)', () {
    expect(run([(0, c), (1, s), (30, s), (61, s), (90, s), (121, s), (122, s)]),
        [c, c, c, w, w, s, s]);
  });

  test('a relapse restarts the clock', () {
    expect(run([(0, c), (1, s), (50, c), (51, s), (100, s), (112, s)]),
        [c, c, c, c, c, w]);
  });

  test("Bob's demo episodes never flicker", () {
    final t0 = DateTime(2026, 11, 19, 9);
    Severity? last;
    DateTime? changedAt;
    var sawCritical = false;
    for (var t = Duration.zero;
        t < const Duration(minutes: 30);
        t += mockVitalsInterval) {
      final now = t0.add(t);
      final sev = mockReading(kBobId, now).severity;
      sawCritical |= sev == c;
      if (last != null && sev != last) {
        if (sev.index < last.index) {
          expect(last.index - sev.index, 1,
              reason: 'jumped $last -> $sev at $t');
          expect(now.difference(changedAt!), greaterThanOrEqualTo(latchHold),
              reason: 'stepped down too soon at $t');
        }
        changedAt = now;
      }
      last = sev;
      changedAt ??= now;
    }
    expect(sawCritical, isTrue, reason: 'Bob has an episode every 4 minutes');
  });
}
