from datetime import datetime
from unittest import mock

import pytest

import simulator
from simulator import Patient

PID = "7c9e6679-7425-40de-944b-e07fc1f90ae7"


def readings(scenario: str, seconds: int, seed: int = 1) -> list[dict]:
    """Simulate `seconds` one-second ticks without waiting."""
    clock = mock.patch.object(simulator.time, "monotonic")
    with clock as monotonic:
        monotonic.return_value = 0.0
        patient = Patient(PID, scenario, seed=seed)
        out = []
        for t in range(seconds):
            monotonic.return_value = float(t)
            out.append(patient.reading())
        return out


@pytest.mark.parametrize("scenario", simulator.SCENARIOS)
def test_every_reading_satisfies_the_engine_schema(scenario):
    # Mirrors the Telemetry Engine's Pydantic bounds (app/schemas.py).
    for r in readings(scenario, 600):
        assert set(r) == {"patientId", "heartRate", "spo2", "systolicBP", "diastolicBP", "timestamp"}
        assert 20 <= r["heartRate"] <= 250
        assert 50 <= r["spo2"] <= 100
        assert 40 <= r["systolicBP"] <= 300
        assert 20 <= r["diastolicBP"] < r["systolicBP"]
        assert datetime.fromisoformat(r["timestamp"]).tzinfo is not None


def test_stable_patient_stays_in_normal_range():
    for r in readings("stable", 300):
        assert 55 < r["heartRate"] < 105
        assert r["spo2"] > 94


def test_acute_episodes_build_hold_and_recover_like_real_ones():
    hr = [r["heartRate"] for r in readings("acute_events", 380)]
    assert max(hr[:60]) < 105  # calm for the first minute
    assert min(hr[95:140]) > 130  # the episode holds for about 45 s
    assert max(hr[175:300]) < 105  # then passes
    assert min(hr[340:]) > 130  # and comes back 4 minutes after the first
    # No jumps: it builds over half a minute rather than spiking.
    assert max(abs(a - b) for a, b in zip(hr, hr[1:], strict=False)) < 10


def test_deterioration_crosses_into_critical_then_recovers():
    # 12-minute cycle: a slow 10-minute decline, then 2 minutes of recovery.
    rs = readings("deteriorating", 720)
    assert rs[10]["spo2"] > 94  # early: fine
    assert rs[120]["heartRate"] < 110 and rs[120]["spo2"] > 94  # 2 min in: still "normal"
    assert min(r["spo2"] for r in rs[520:605]) < 90  # late in the decline: critical
    assert rs[719]["heartRate"] < rs[600]["heartRate"]  # recovering


def test_values_drift_smoothly_rather_than_jumping():
    hr = [r["heartRate"] for r in readings("stable", 200)]
    assert max(abs(a - b) for a, b in zip(hr, hr[1:], strict=False)) < 10


def test_unknown_scenario_is_rejected():
    with pytest.raises(ValueError):
        Patient(PID, "teleporting")
