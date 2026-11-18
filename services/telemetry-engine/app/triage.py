"""Threshold triage for adult post-cardiac-surgery patients: each reading is
stable, warning or critical, with the reasons.

The app applies the same rules in mock mode
(lib/src/features/vitals_monitor/domain/triage.dart): keep them in sync.
"""

import math
from dataclasses import dataclass, field
from enum import StrEnum


class Severity(StrEnum):
    STABLE = "stable"
    WARNING = "warning"
    CRITICAL = "critical"


HR_CRITICAL_LOW = 40.0
HR_WARNING_LOW = 50.0
HR_WARNING_HIGH = 110.0
HR_CRITICAL_HIGH = 130.0

SPO2_CRITICAL_LOW = 90.0
SPO2_WARNING_LOW = 94.0

SYS_CRITICAL_LOW = 90.0
SYS_WARNING_LOW = 100.0
SYS_WARNING_HIGH = 160.0
SYS_CRITICAL_HIGH = 180.0


@dataclass(frozen=True)
class TriageResult:
    severity: Severity
    alerts: list[str] = field(default_factory=list)


def _round(value: float) -> int:
    """Round half away from zero, matching Dart's num.round() in the app."""
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def evaluate(heart_rate: float, spo2: float, systolic_bp: float) -> TriageResult:
    critical: list[str] = []
    warning: list[str] = []

    hr = _round(heart_rate)
    if heart_rate > HR_CRITICAL_HIGH:
        critical.append(f"Heart rate very high ({hr} bpm)")
    elif heart_rate < HR_CRITICAL_LOW:
        critical.append(f"Heart rate very low ({hr} bpm)")
    elif heart_rate > HR_WARNING_HIGH:
        warning.append(f"Heart rate elevated ({hr} bpm)")
    elif heart_rate < HR_WARNING_LOW:
        warning.append(f"Heart rate low ({hr} bpm)")

    o2 = _round(spo2)
    if spo2 < SPO2_CRITICAL_LOW:
        critical.append(f"Oxygen saturation critical ({o2}%)")
    elif spo2 < SPO2_WARNING_LOW:
        warning.append(f"Oxygen saturation low ({o2}%)")

    sys = _round(systolic_bp)
    if systolic_bp > SYS_CRITICAL_HIGH:
        critical.append(f"Blood pressure very high ({sys} systolic)")
    elif systolic_bp < SYS_CRITICAL_LOW:
        critical.append(f"Blood pressure very low ({sys} systolic)")
    elif systolic_bp > SYS_WARNING_HIGH:
        warning.append(f"Blood pressure elevated ({sys} systolic)")
    elif systolic_bp < SYS_WARNING_LOW:
        warning.append(f"Blood pressure low ({sys} systolic)")

    if critical:
        severity = Severity.CRITICAL
    elif warning:
        severity = Severity.WARNING
    else:
        severity = Severity.STABLE
    return TriageResult(severity, critical + warning)
