// Alarm latching, mirroring services/telemetry-engine/app/latch.py (keep in
// sync): status escalates on the first worse reading but steps down one level
// only after readings stay calmer for a minute, so it doesn't flicker.

import 'triage.dart';

const latchHold = Duration(seconds: 60);

/// Alert added while a status is held above what the reading alone shows.
const latchHoldAlert =
    'Back in range: holding this status for a minute to confirm';

class StatusLatch {
  Severity? _shown;
  DateTime? _calmSince;

  /// The status to show for a reading of [severity] at [at], and whether it
  /// is being held above the reading.
  (Severity, bool) update(DateTime at, Severity severity) {
    final shown = _shown;
    if (shown == null || severity.index >= shown.index) {
      _shown = severity;
      _calmSince = null;
      return (severity, false);
    }
    final since = _calmSince;
    if (since == null) {
      _calmSince = at;
    } else if (at.difference(since) >= latchHold) {
      final lowered = Severity.values[shown.index - 1]; // one level at a time
      _shown = lowered;
      _calmSince = severity.index < lowered.index ? at : null;
    }
    return (_shown!, _shown!.index > severity.index);
  }
}
