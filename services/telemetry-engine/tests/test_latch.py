import uuid
from datetime import UTC, datetime, timedelta

from app.latch import StatusLatch
from app.triage import Severity

from .conftest import BOB, DEVICE_KEY, auth, reading

S, W, C = Severity.STABLE, Severity.WARNING, Severity.CRITICAL
START = datetime(2026, 1, 1, tzinfo=UTC)


def run(raw: list[tuple[int, Severity]]) -> list[Severity]:
    """Feeds (second, raw severity) pairs; returns the status shown each time."""
    latch, patient = StatusLatch(), uuid.uuid4()
    return [latch.update(patient, START + timedelta(seconds=t), sev)[0] for t, sev in raw]


def test_escalates_on_the_first_bad_reading():
    assert run([(0, S), (1, C)]) == [S, C]


def test_steps_down_one_level_per_calm_minute():
    shown = run([(0, C), (1, S), (30, S), (61, S), (90, S), (121, S), (122, S)])
    # Calm from 1 s: warning after a minute, stable after another.
    assert shown == [C, C, C, W, W, S, S]


def test_a_single_good_reading_does_not_clear_an_alarm():
    assert run([(0, C), (1, S), (2, C), (3, S), (4, C)]) == [C, C, C, C, C]


def test_relapse_restarts_the_clock():
    shown = run([(0, C), (1, S), (50, C), (51, S), (100, S), (112, S)])
    assert shown == [C, C, C, C, C, W]  # the minute counts from 51 s, not 1 s


def test_patients_are_tracked_separately():
    latch = StatusLatch()
    a, b = uuid.uuid4(), uuid.uuid4()
    latch.update(a, START, C)
    assert latch.update(b, START, S)[0] == S


def test_the_pipeline_holds_the_status_and_says_why(client):
    now = datetime.now(UTC)
    headers = {"X-Device-Key": DEVICE_KEY}
    critical = reading(BOB, heartRate=145, spo2=86, timestamp=(now - timedelta(seconds=10)).isoformat())
    calm = reading(BOB, timestamp=(now - timedelta(seconds=5)).isoformat())
    assert client.post("/telemetry", json=critical, headers=headers).json()["severity"] == "critical"
    assert client.post("/telemetry", json=calm, headers=headers).json()["severity"] == "critical"

    latest = client.get(f"/vitals/{BOB}/history?limit=1", headers=auth(BOB, "patient")).json()["vitals"][-1]
    assert latest["heartRate"] == 74 and latest["severity"] == "critical"
    assert any("holding this status" in a for a in latest["alerts"])
