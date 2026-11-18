import time
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.db import VitalsRecord

from .conftest import DOCTOR, JANE, JOHN, NURSE, auth, ingest, reading, token


def test_ingest_requires_a_known_device(client):
    assert client.post("/telemetry", json=reading()).status_code == 401
    bad = client.post("/telemetry", json=reading(), headers={"X-Device-Key": "wrong"})
    assert bad.status_code == 401


@pytest.mark.parametrize(
    "overrides",
    [
        {"spo2": 120},  # out of physiological range
        {"heartRate": "fast"},  # wrong type
        {"diastolicBP": 130},  # diastolic above systolic
        {"timestamp": "2026-10-28T10:00:00"},  # no timezone
        {"timestamp": (datetime.now(UTC) + timedelta(hours=1)).isoformat()},  # future
        {"patientId": "patient-001"},  # not a pseudonymized UUID
        {"name": "John Doe"},  # unexpected field: names never enter telemetry
    ],
)
def test_invalid_payloads_are_rejected(client, overrides):
    assert ingest(client, **overrides).status_code == 422


def test_ingest_triages_and_reports_processing_time(client):
    response = ingest(client, heartRate=142)
    assert response.status_code == 202
    assert response.json()["severity"] == "critical"
    assert response.json()["processingMs"] < 2000


def test_vitals_are_encrypted_at_rest(client):
    ingest(client, heartRate=87.25)

    async def raw_rows():
        async with client.app.state.db.sessions() as s:
            return (await s.scalars(select(VitalsRecord))).all()

    rows = client.portal.call(raw_rows)
    assert len(rows) == 1
    assert b"87.25" not in rows[0].payload and b"heartRate" not in rows[0].payload


def test_history_is_decrypted_oldest_first(client):
    now = datetime.now(UTC)
    for i, hr in enumerate([70, 75, 80]):
        ingest(client, heartRate=hr, timestamp=(now - timedelta(seconds=10 - i)).isoformat())

    body = client.get(f"/vitals/{JOHN}/history", headers=auth(JOHN, "patient")).json()
    assert [v["heartRate"] for v in body["vitals"]] == [70, 75, 80]
    assert body["vitals"][0]["severity"] == "stable"
    assert set(body["vitals"][0]) == {
        "patientId",
        "heartRate",
        "spo2",
        "systolicBP",
        "diastolicBP",
        "timestamp",
        "severity",
        "alerts",
    }


def test_patients_only_see_their_own_record(client):
    assert client.get(f"/vitals/{JANE}/history", headers=auth(JOHN, "patient")).status_code == 403
    assert client.get(f"/vitals/{JANE}/history", headers=auth(NURSE, "nurse")).status_code == 200
    assert client.get(f"/vitals/{JANE}/history", headers=auth(DOCTOR, "doctor")).status_code == 200


def test_tokens_are_verified(client):
    url = f"/vitals/{JOHN}/history"
    assert client.get(url).status_code == 401
    expired = token(JOHN, "patient", expires_in=-10)
    assert client.get(url, headers={"Authorization": f"Bearer {expired}"}).status_code == 401
    foreign = token(JOHN, "patient", issuer="someone-else")
    assert client.get(url, headers={"Authorization": f"Bearer {foreign}"}).status_code == 401
    # Algorithm confusion: an HS256 token "signed" with the public key must fail.
    assert client.get(url, headers={"Authorization": f"Bearer {_forged_hs256()}"}).status_code == 401


def _forged_hs256() -> str:
    """Classic attack: sign with HMAC using the server's *public* key as the secret.
    Built by hand because PyJWT itself refuses to produce it."""
    import base64
    import hashlib
    import hmac
    import json

    from .conftest import PUBLIC_PEM

    def b64(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    now = int(datetime.now(UTC).timestamp())
    header = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    claims = {
        "sub": str(JOHN),
        "role": "doctor",
        "iss": "medvitals-identity",
        "aud": "medvitals-api",
        "exp": now + 600,
    }
    body = b64(json.dumps(claims).encode())
    signature = hmac.new(PUBLIC_PEM.encode(), f"{header}.{body}".encode(), hashlib.sha256).digest()
    return f"{header}.{body}.{b64(signature)}"


def test_single_tap_escalation_lifecycle(client):
    ingest(client, systolicBP=165)  # a warning-level reading to attach

    created = client.post("/escalations", json={"patientId": str(JOHN)}, headers=auth(JOHN, "patient"))
    assert created.status_code == 201
    esc = created.json()
    assert esc["status"] == "pending" and esc["source"] == "patient"
    assert esc["severity"] == "warning" and esc["alerts"] == ["Blood pressure elevated (165 systolic)"]

    # Tapping again while it is open returns the same request.
    again = client.post("/escalations", json={"patientId": str(JOHN)}, headers=auth(JOHN, "patient"))
    assert again.status_code == 200 and again.json()["id"] == esc["id"]

    # Patients cannot acknowledge; nurses can.
    url = f"/escalations/{esc['id']}"
    assert (
        client.patch(url, json={"status": "acknowledged"}, headers=auth(JOHN, "patient")).status_code == 403
    )
    acked = client.patch(url, json={"status": "acknowledged"}, headers=auth(NURSE, "nurse"))
    assert acked.status_code == 200
    assert acked.json()["acknowledgedBy"] == str(NURSE)

    resolved = client.patch(url, json={"status": "resolved"}, headers=auth(NURSE, "nurse")).json()
    assert resolved["status"] == "resolved" and "resolvedAt" in resolved
    # Resolved is final.
    assert client.patch(url, json={"status": "acknowledged"}, headers=auth(NURSE, "nurse")).status_code == 409


def test_cannot_escalate_for_someone_else_or_claim_auto(client):
    other = client.post("/escalations", json={"patientId": str(JANE)}, headers=auth(JOHN, "patient"))
    assert other.status_code == 403
    auto = client.post(
        "/escalations", json={"patientId": str(JOHN), "source": "auto"}, headers=auth(JOHN, "patient")
    )
    assert auto.status_code == 422


def test_critical_reading_escalates_automatically_once(client):
    ingest(client, patient=JANE, spo2=86)
    ingest(client, patient=JANE, spo2=85)

    queue = client.get("/escalations", headers=auth(NURSE, "nurse")).json()["escalations"]
    assert len(queue) == 1
    assert queue[0]["source"] == "auto" and queue[0]["severity"] == "critical"
    assert queue[0]["patientId"] == str(JANE)

    # Jane sees her own; John sees none of hers.
    assert len(client.get("/escalations", headers=auth(JANE, "patient")).json()["escalations"]) == 1
    assert client.get("/escalations", headers=auth(JOHN, "patient")).json()["escalations"] == []


def test_monitor_stream_delivers_triaged_readings_under_two_seconds(client):
    with client.websocket_connect(f"/monitor/stream?token={token(DOCTOR, 'doctor')}") as ws:
        generated = datetime.now(UTC)
        started = time.perf_counter()
        ingest(client, heartRate=135, timestamp=generated.isoformat())
        event = ws.receive_json()
        elapsed = time.perf_counter() - started

    assert event["patientId"] == str(JOHN)
    assert event["severity"] == "critical"
    assert elapsed < 2.0  # the 2-second end-to-end budget


def test_patient_stream_only_carries_that_patient(client):
    with client.websocket_connect(f"/vitals/{JOHN}/stream?token={token(JOHN, 'patient')}") as ws:
        ingest(client, patient=JANE)
        ingest(client, patient=JOHN, heartRate=81)
        assert ws.receive_json()["heartRate"] == 81


@pytest.mark.parametrize(
    ("path", "user", "role"),
    [
        (f"/vitals/{JANE}/stream", JOHN, "patient"),  # someone else's record
        ("/monitor/stream", JOHN, "patient"),  # care team only
    ],
)
def test_streams_enforce_roles(client, path, user, role):
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect) as closed:
        with client.websocket_connect(f"{path}?token={token(user, role)}") as ws:
            ws.receive_json()
    assert closed.value.code == 4403


def test_streams_require_a_token(client):
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect) as closed:
        with client.websocket_connect("/monitor/stream") as ws:
            ws.receive_json()
    assert closed.value.code == 4401


def test_escalation_stream_notifies_the_nurse(client):
    with client.websocket_connect(f"/escalations/stream?token={token(NURSE, 'nurse')}") as ws:
        client.post("/escalations", json={"patientId": str(JOHN)}, headers=auth(JOHN, "patient"))
        event = ws.receive_json()
    assert event["type"] == "escalation" and event["patientId"] == str(JOHN)


def test_health_ready_and_security_headers(client):
    assert client.get("/health").json() == {"status": "ok"}
    ready = client.get("/ready")
    assert ready.status_code == 200 and ready.json()["database"] is True
    assert ready.headers["cache-control"] == "no-store"
    assert ready.headers["x-content-type-options"] == "nosniff"
