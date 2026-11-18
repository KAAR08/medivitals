"""Trend-based deterioration alerts (early warning)."""

import random
import uuid
from datetime import UTC, datetime, timedelta

from app.trends import TrendTracker, detect

from .conftest import DEVICE_KEY, JOHN, NURSE, auth, reading


def series(minutes: float, every: float = 5.0, hr=(75, 75), spo2=(97, 97), sys=(122, 122), noise=0.0):
    """Readings drifting linearly from start to end values, oldest first."""
    rng = random.Random(7)  # noqa: S311 - test noise, not security
    n = int(minutes * 60 / every) + 1
    out = []
    for i in range(n):
        f = i / (n - 1)

        def at(a, b, f=f):
            return a + (b - a) * f + rng.uniform(-noise, noise)

        out.append((i * every, at(*hr), at(*spo2), at(*sys)))
    return out


def test_steady_noisy_vitals_raise_nothing():
    assert detect(series(5, hr=(76, 76), spo2=(97, 97), sys=(122, 122), noise=4)) == []


def test_each_worrying_direction_is_detected():
    trends = detect(series(4, hr=(76, 96), spo2=(97, 93), sys=(124, 100)))
    assert [t.vital for t in trends] == ["heartRate", "spo2", "systolicBP"]
    assert trends[0].alert == "Trend: heart rate rising (+20 bpm over 4 min)"
    assert trends[1].alert == "Trend: oxygen saturation falling (-4% over 4 min)"
    assert trends[2].alert == "Trend: blood pressure falling (-24 systolic over 4 min)"


def test_improving_vitals_are_not_flagged():
    # Heart rate falling, oxygen rising, blood pressure rising: recovery.
    assert detect(series(4, hr=(100, 78), spo2=(93, 97), sys=(100, 124))) == []


def test_needs_enough_data():
    assert detect(series(1, hr=(70, 110))) == []  # under 2 minutes
    assert detect(series(3, every=20, hr=(70, 110))) == []  # too few points


def test_one_spike_is_not_a_trend():
    samples = series(4, noise=1)
    samples[-1] = (samples[-1][0], 140, 85, 90)  # a single wild reading
    assert detect(samples) == []


def test_tracker_keeps_only_the_window():
    tracker = TrendTracker()
    patient = uuid.uuid4()
    start = datetime(2026, 1, 1, tzinfo=UTC)
    # Ten minutes of rising heart rate, then five steady minutes at the top.
    for i in range(120):
        tracker.add(patient, start + timedelta(seconds=5 * i), 70 + i * 0.25, 97, 122)
    trends = []
    for i in range(120, 181):
        trends = tracker.add(patient, start + timedelta(seconds=5 * i), 100, 97, 122)
    assert trends == []  # the rise is older than the 5-minute window


def ingest_series(client, samples, patient=JOHN):
    start = datetime.now(UTC) - timedelta(seconds=samples[-1][0] + 1)
    last = None
    for t, hr, spo2, sys in samples:
        body = reading(
            patient,
            heartRate=round(hr, 1),
            spo2=round(spo2, 1),
            systolicBP=round(sys, 1),
            diastolicBP=70,
            timestamp=(start + timedelta(seconds=t)).isoformat(),
        )
        last = client.post("/telemetry", json=body, headers={"X-Device-Key": DEVICE_KEY})
        assert last.status_code == 202
    return last


def open_cases(client):
    return client.get("/escalations", headers=auth(NURSE, "nurse")).json()["escalations"]


def test_single_trend_raises_a_warning_but_no_case(client):
    # Heart rate climbing 76 -> 100: every reading is still "normal" (< 110).
    last = ingest_series(client, series(4, hr=(76, 100)))
    assert last.json()["severity"] == "warning"
    history = client.get(f"/vitals/{JOHN}/history?limit=1", headers=auth(JOHN, "patient")).json()
    assert any(a.startswith("Trend: heart rate rising") for a in history["vitals"][-1]["alerts"])
    assert open_cases(client) == []


def test_deteriorating_together_opens_an_early_warning_case(client):
    # Heart rate up and oxygen down, each still inside normal limits.
    ingest_series(client, series(4, hr=(76, 100), spo2=(98, 94.5)))
    cases = open_cases(client)
    assert len(cases) == 1
    case = cases[0]
    assert case["source"] == "auto" and case["severity"] == "warning"
    assert case["note"].startswith("Early warning")
    assert any("oxygen saturation falling" in a for a in case["alerts"])
