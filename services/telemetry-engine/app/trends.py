"""Trend-based deterioration alerts (early warning).

Threshold triage (triage.py) looks at one reading. Patients usually
deteriorate gradually: heart rate creeping up, oxygen and blood pressure
sliding, each still "normal". This looks at the last few minutes per patient
and flags a sustained drift in a worrying direction, before any single
reading crosses a threshold.

Method: a least-squares line through each vital over the window; the drift is
the line's change across the window, so one noisy reading can't trigger it.

- One worrying trend raises the reading to at least WARNING.
- Two or more together (multi-parameter deterioration) are an early warning:
  the engine opens a case for the triage nurse automatically.

This is decision support on simulated data, not a diagnosis. Keep in sync with
lib/src/features/vitals_monitor/domain/trend.dart in the app (mock mode).
"""

import math
import uuid
from collections import deque
from dataclasses import dataclass
from datetime import datetime

WINDOW_SECONDS = 300.0  # look back 5 minutes
MIN_SPAN_SECONDS = 120.0  # need at least 2 minutes of data...
MIN_READINGS = 20  # ...and enough points for a stable fit

HR_RISE = 15.0  # bpm across the window
SPO2_DROP = 3.0  # percentage points
SYS_DROP = 20.0  # mmHg


@dataclass(frozen=True)
class Trend:
    vital: str  # heartRate | spo2 | systolicBP
    change: float  # across the window, in the vital's unit
    minutes: float

    @property
    def alert(self) -> str:
        m = max(1, int(math.floor(self.minutes + 0.5)))
        change = int(math.floor(abs(self.change) + 0.5))
        match self.vital:
            case "heartRate":
                return f"Trend: heart rate rising (+{change} bpm over {m} min)"
            case "spo2":
                return f"Trend: oxygen saturation falling (-{change}% over {m} min)"
            case _:
                return f"Trend: blood pressure falling (-{change} systolic over {m} min)"


def slope_per_second(times: list[float], values: list[float]) -> float:
    n = len(times)
    mean_t = sum(times) / n
    mean_v = sum(values) / n
    var = sum((t - mean_t) ** 2 for t in times)
    if var == 0:
        return 0.0
    return sum((t - mean_t) * (v - mean_v) for t, v in zip(times, values, strict=True)) / var


def detect(samples: list[tuple[float, float, float, float]]) -> list[Trend]:
    """samples: (seconds, heart rate, SpO2, systolic), oldest first."""
    if len(samples) < MIN_READINGS:
        return []
    span = samples[-1][0] - samples[0][0]
    if span < MIN_SPAN_SECONDS:
        return []
    times = [s[0] for s in samples]
    trends: list[Trend] = []
    for index, vital, threshold, rising in (
        (1, "heartRate", HR_RISE, True),
        (2, "spo2", SPO2_DROP, False),
        (3, "systolicBP", SYS_DROP, False),
    ):
        change = slope_per_second(times, [s[index] for s in samples]) * span
        if (rising and change >= threshold) or (not rising and change <= -threshold):
            trends.append(Trend(vital, change, span / 60))
    return trends


class TrendTracker:
    """Each patient's recent readings, in memory.

    Per engine instance: after a restart the window refills within minutes.
    With several instances behind a load balancer, route each device to one
    instance (sticky) or move this window into Redis.
    """

    def __init__(self) -> None:
        self._windows: dict[uuid.UUID, deque[tuple[float, float, float, float]]] = {}

    def add(
        self, patient_id: uuid.UUID, at: datetime, hr: float, spo2: float, systolic: float
    ) -> list[Trend]:
        window = self._windows.setdefault(patient_id, deque())
        t = at.timestamp()
        if window and t < window[-1][0]:
            return detect(list(window))  # out-of-order reading: don't corrupt the window
        window.append((t, hr, spo2, systolic))
        while window and window[0][0] < t - WINDOW_SECONDS:
            window.popleft()
        return detect(list(window))
