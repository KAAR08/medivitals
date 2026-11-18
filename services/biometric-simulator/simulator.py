"""Simulated wearables: posts plausible vitals for the demo patients to the
engine, the way a real device gateway would.

Each patient follows a recovery scenario:
  stable         - normal post-op recovery, small natural variation
  borderline     - blood pressure hovering around the upper limit (warnings)
  deteriorating  - slow decline over ~10 minutes into critical, then recovery
                   (the trend alerts flag it minutes before any threshold)
  acute_events   - stable, with an episode every 4 minutes (tachycardia with
                   desaturation: builds over 30 s, holds 45 s, eases over 30 s);
                   the first one starts a minute after launch

Values follow a mean-reverting random walk (Ornstein-Uhlenbeck), so they drift
smoothly the way real vitals do instead of jumping randomly every second.

Configuration (environment):
  SIM_ENGINE_URL   Telemetry Engine base URL      (default http://127.0.0.1:8000)
  SIM_DEVICE_KEY   device API key (or SIM_DEVICE_KEY_FILE: a file holding it)
  SIM_INTERVAL     seconds between readings       (default 1.0)
  SIM_PATIENTS     JSON {"<uuid>": "<scenario>"}  (default: the three demo patients)
  SIM_VERIFY_TLS   "false" to accept the dev gateway's self-signed certificate
"""

import asyncio
import json
import logging
import math
import os
import random
import signal
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import httpx

log = logging.getLogger("simulator")

# Same pseudonymized IDs as the Identity Service seed and the app's mock data.
DEFAULT_PATIENTS = {
    "7c9e6679-7425-40de-944b-e07fc1f90ae7": "stable",  # John Doe
    "2f1a8b3c-9d4e-4f5a-8b6c-7d8e9f0a1b2c": "deteriorating",  # Jane Smith
    "9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d": "acute_events",  # Bob Wilson
}

SCENARIOS = ("stable", "borderline", "deteriorating", "acute_events")


@dataclass
class _Signal:
    """One vital sign as a mean-reverting random walk."""

    mean: float
    volatility: float
    reversion: float = 0.15
    value: float = field(init=False)

    def __post_init__(self) -> None:
        self.value = self.mean

    def step(self, rng: random.Random, target: float | None = None) -> float:
        goal = self.mean if target is None else target
        self.value += self.reversion * (goal - self.value) + rng.gauss(0, self.volatility)
        return self.value


class Patient:
    def __init__(self, patient_id: str, scenario: str, seed: int | None = None) -> None:
        if scenario not in SCENARIOS:
            raise ValueError(f"Unknown scenario {scenario!r}; choose one of {SCENARIOS}")
        self.patient_id = patient_id
        self.scenario = scenario
        self._rng = random.Random(seed)
        self._started = time.monotonic()
        baseline_sys = 156.0 if scenario == "borderline" else 122.0
        self._hr = _Signal(mean=76.0, volatility=1.2)
        self._spo2 = _Signal(mean=97.2, volatility=0.25)
        self._sys = _Signal(mean=baseline_sys, volatility=1.5, reversion=0.08)
        self._dia = _Signal(mean=baseline_sys * 0.62, volatility=1.0)

    def _targets(self, t: float) -> tuple[float | None, float | None, float | None]:
        """Where each signal is heading at elapsed time t (seconds)."""
        if self.scenario == "deteriorating":
            # 12-minute cycle: decline for 10 minutes, recover for 2.
            phase = (t % 720) / 600
            if phase <= 1:
                return 76 + 58 * phase, 97.2 - 9 * phase, 122 - 30 * phase
            return None, None, None
        if self.scenario == "acute_events":
            level = _episode((t + 30) % 240)
            if level > 0:
                return 76 + 69 * level, 97.2 - 11.2 * level, None  # peaks: 145 bpm, 86 %
        return None, None, None

    def reading(self, now: datetime | None = None) -> dict:
        t = time.monotonic() - self._started
        hr_t, spo2_t, sys_t = self._targets(t)

        hr = self._hr.step(self._rng, hr_t)
        spo2 = self._spo2.step(self._rng, spo2_t)
        systolic = self._sys.step(self._rng, sys_t)
        diastolic = self._dia.step(self._rng, None if sys_t is None else sys_t * 0.62)

        systolic = _clamp(systolic, 70, 220)
        return {
            "patientId": self.patient_id,
            "heartRate": round(_clamp(hr, 35, 200), 1),
            "spo2": round(_clamp(spo2, 75, 100), 1),
            "systolicBP": round(systolic, 1),
            "diastolicBP": round(_clamp(diastolic, 40, systolic - 15), 1),
            "timestamp": (now or datetime.now(UTC)).isoformat(),
        }


def _episode(t: float) -> float:
    """0..1 intensity of an acute episode at t seconds into a 4-minute cycle:
    calm until 1:30, builds over 30 s, holds 45 s, eases over 30 s."""
    if t < 90 or t >= 195:
        return 0.0
    if t < 120:
        return (t - 90) / 30
    if t < 165:
        return 1.0
    return (195 - t) / 30


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value)) if not math.isnan(value) else low


async def run(
    engine_url: str,
    device_key: str,
    patients: list[Patient],
    interval: float,
    verify_tls: bool = True,
    stop: asyncio.Event | None = None,
) -> None:
    stop = stop or asyncio.Event()
    headers = {"X-Device-Key": device_key}
    backoff = 1.0
    async with httpx.AsyncClient(
        base_url=engine_url, headers=headers, timeout=5, verify=verify_tls
    ) as client:
        while not stop.is_set():
            tick = time.monotonic()
            try:
                results = await asyncio.gather(
                    *(client.post("/telemetry", json=p.reading()) for p in patients)
                )
                for p, r in zip(patients, results, strict=True):
                    if r.status_code != 202:
                        log.warning("%s rejected: %s %s", p.patient_id[:8], r.status_code, r.text[:200])
                    elif r.json()["severity"] != "stable":
                        log.info("%s -> %s", p.patient_id[:8], r.json()["severity"])
                backoff = 1.0
            except httpx.HTTPError as e:
                log.warning("Engine unreachable (%s); retrying in %.0f s", e.__class__.__name__, backoff)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 30)
                continue
            await asyncio.sleep(max(0.0, interval - (time.monotonic() - tick)))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)  # one line per request is too noisy
    key_file = os.environ.get("SIM_DEVICE_KEY_FILE")
    device_key = (
        Path(key_file).read_text(encoding="utf-8").strip() if key_file else os.environ.get("SIM_DEVICE_KEY")
    )
    if not device_key:
        raise SystemExit("SIM_DEVICE_KEY is required")
    mapping = json.loads(os.environ["SIM_PATIENTS"]) if os.environ.get("SIM_PATIENTS") else DEFAULT_PATIENTS
    patients = [Patient(pid, scenario) for pid, scenario in mapping.items()]
    engine_url = os.environ.get("SIM_ENGINE_URL", "http://127.0.0.1:8000")
    interval = float(os.environ.get("SIM_INTERVAL", "1.0"))
    verify_tls = os.environ.get("SIM_VERIFY_TLS", "true").lower() != "false"

    log.info("Streaming %d patients to %s every %.1f s", len(patients), engine_url, interval)
    stop = asyncio.Event()

    async def _main() -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, stop.set)
            except NotImplementedError:  # Windows: Ctrl+C raises KeyboardInterrupt instead
                pass
        await run(engine_url, device_key, patients, interval, verify_tls, stop)

    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
