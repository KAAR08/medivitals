"""Alarm latching, as bedside monitors do it.

A patient's status escalates on the first worse reading, but only steps down
one level once readings have stayed calmer for HOLD_SECONDS, so it doesn't
flicker between critical and stable while vitals hover near a threshold.

In memory, per engine instance (like the trend windows).
"""

import uuid
from dataclasses import dataclass
from datetime import datetime

from .triage import Severity

HOLD_SECONDS = 60.0
_ORDER = [Severity.STABLE, Severity.WARNING, Severity.CRITICAL]


@dataclass
class _State:
    shown: Severity
    calm_since: float | None = None


class StatusLatch:
    def __init__(self) -> None:
        self._patients: dict[uuid.UUID, _State] = {}

    def update(self, patient_id: uuid.UUID, at: datetime, severity: Severity) -> tuple[Severity, bool]:
        """Returns (status to show, whether it's being held above the reading)."""
        t = at.timestamp()
        state = self._patients.get(patient_id)
        if state is None:
            self._patients[patient_id] = _State(severity)
            return severity, False

        rank, shown = _ORDER.index(severity), _ORDER.index(state.shown)
        if rank >= shown:
            state.shown, state.calm_since = severity, None
            return severity, False

        if state.calm_since is None:
            state.calm_since = t
        elif t - state.calm_since >= HOLD_SECONDS:
            state.shown = _ORDER[shown - 1]  # one level at a time
            state.calm_since = t if rank < shown - 1 else None
        return state.shown, _ORDER.index(state.shown) > rank
