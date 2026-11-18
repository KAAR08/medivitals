"""Escalation outcomes and voice/video call signalling."""

import base64
import hashlib
import hmac
import sqlite3
import uuid

import pytest
from fastapi.testclient import TestClient

from app.main import create_app

from .conftest import DOCTOR, JANE, JOHN, NURSE, auth, token


def signal_socket(client: TestClient, user: uuid.UUID, role: str):
    return client.websocket_connect(f"/calls/signal?token={token(user, role)}")


def next_of(ws, kind: str) -> dict:
    """Next message of the given type (skipping others)."""
    while True:
        msg = ws.receive_json()
        if msg["type"] == kind:
            return msg
        if msg["type"] == "error":
            raise AssertionError(f"unexpected error: {msg}")


def request_callback(client: TestClient, patient: uuid.UUID = JOHN) -> dict:
    r = client.post("/escalations", json={"patientId": str(patient)}, headers=auth(patient, "patient"))
    assert r.status_code == 201
    return r.json()


def case(client: TestClient, escalation_id: str) -> dict:
    cases = client.get("/escalations", headers=auth(NURSE, "nurse")).json()["escalations"]
    return next(e for e in cases if e["id"] == escalation_id)


def test_nurse_can_refer_then_doctor_dispatches_ambulance(client):
    esc = request_callback(client)
    r = client.patch(
        f"/escalations/{esc['id']}",
        json={"status": "referred", "note": "Chest pain, needs cardiology review"},
        headers=auth(NURSE, "nurse"),
    )
    assert r.status_code == 200 and r.json()["status"] == "referred"

    r = client.patch(
        f"/escalations/{esc['id']}",
        json={"status": "ambulance", "note": "Sent to ER"},
        headers=auth(DOCTOR, "doctor"),
    )
    assert r.json()["status"] == "ambulance"
    r = client.patch(f"/escalations/{esc['id']}", json={"status": "resolved"}, headers=auth(DOCTOR, "doctor"))
    body = r.json()
    assert body["status"] == "resolved" and body["resolvedAt"]
    assert [e["action"] for e in body["timeline"]] == ["raised", "referred", "ambulance", "resolved"]
    assert body["timeline"][1] == {
        **body["timeline"][1],
        "role": "nurse",
        "by": str(NURSE),
        "note": "Chest pain, needs cardiology review",
    }


def test_outcomes_follow_the_workflow(client):
    esc = request_callback(client)
    nurse = auth(NURSE, "nurse")
    assert (
        client.patch(f"/escalations/{esc['id']}", json={"status": "resolved"}, headers=nurse).status_code
        == 200
    )
    r = client.patch(f"/escalations/{esc['id']}", json={"status": "referred"}, headers=nurse)
    assert r.status_code == 409
    esc = request_callback(client)  # a new case can open once the last is resolved
    client.patch(f"/escalations/{esc['id']}", json={"status": "ambulance"}, headers=nurse)
    r = client.patch(f"/escalations/{esc['id']}", json={"status": "referred"}, headers=nurse)
    assert r.status_code == 409  # an ambulance case can only be resolved


def test_patients_cannot_record_outcomes(client):
    esc = request_callback(client)
    r = client.patch(f"/escalations/{esc['id']}", json={"status": "resolved"}, headers=auth(JOHN, "patient"))
    assert r.status_code == 403


def test_outcome_notes_are_encrypted_at_rest(client, settings):
    esc = request_callback(client)
    client.patch(
        f"/escalations/{esc['id']}",
        json={"status": "referred", "note": "SECRET-CLINICAL-NOTE"},
        headers=auth(NURSE, "nurse"),
    )
    db_path = settings.database_url.split("///", 1)[1]
    with sqlite3.connect(db_path) as conn:
        blobs = [row[0] for row in conn.execute("SELECT payload FROM escalations")]
    assert blobs and all(b"SECRET-CLINICAL-NOTE" not in blob for blob in blobs)


def test_ice_servers_need_a_token(client):
    assert client.get("/calls/ice-servers").status_code == 401


def test_ice_servers_without_turn(client):
    r = client.get("/calls/ice-servers", headers=auth(JOHN, "patient"))
    assert r.json()["iceServers"] == []


def test_turn_credentials_are_short_lived_and_signed(settings):
    settings = settings.model_copy(update={"turn_urls": ["turn:turn.example:3478"], "turn_secret": "s3cret"})
    with TestClient(create_app(settings)) as client:
        servers = client.get("/calls/ice-servers", headers=auth(JOHN, "patient")).json()["iceServers"]
    turn = servers[0]
    expiry, user = turn["username"].split(":")
    assert user == str(JOHN) and int(expiry) > 0
    expected = base64.b64encode(
        hmac.new(b"s3cret", turn["username"].encode(), hashlib.sha1).digest()
    ).decode()
    assert turn["credential"] == expected


def test_signalling_requires_a_token(client):
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect), client.websocket_connect("/calls/signal") as ws:
        ws.receive_json()


def test_nurse_calls_patient_about_their_case(client):
    esc = request_callback(client)
    call_id = str(uuid.uuid4())
    with signal_socket(client, NURSE, "nurse") as nurse, signal_socket(client, JOHN, "patient") as john:
        nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN), "escalationId": esc["id"]})
        assert next_of(nurse, "ringing")["callId"] == call_id
        incoming = next_of(john, "incoming")
        assert incoming["from"] == {"id": str(NURSE), "role": "nurse"}
        assert incoming["escalationId"] == esc["id"] and incoming["video"] is False
        assert case(client, esc["id"])["status"] == "acknowledged"  # the nurse took the case

        john.send_json({"type": "accept", "callId": call_id})
        assert next_of(nurse, "accepted")["by"]["id"] == str(JOHN)
        next_of(john, "accepted")

        # WebRTC session data is relayed between the two parties only.
        nurse.send_json({"type": "signal", "callId": call_id, "data": {"sdp": "offer", "kind": "offer"}})
        assert next_of(john, "signal")["data"] == {"sdp": "offer", "kind": "offer"}
        john.send_json({"type": "signal", "callId": call_id, "data": {"candidate": "c1"}})
        assert next_of(nurse, "signal")["data"] == {"candidate": "c1"}

        # Switching to video is announced to the other side.
        john.send_json({"type": "media", "callId": call_id, "video": True})
        assert next_of(nurse, "media")["video"] is True

        nurse.send_json({"type": "hangup", "callId": call_id})
        assert next_of(john, "ended")["reason"] == "ended"

    timeline = case(client, esc["id"])["timeline"]
    call = timeline[-1]
    assert call["action"] == "call" and call["outcome"] == "answered" and call["video"] is True


@pytest.mark.parametrize("to", ["nurses", str(NURSE), str(JANE)])
def test_patients_cannot_start_calls(client, to):
    """Patients request a callback; only the care team starts calls."""
    with signal_socket(client, JOHN, "patient") as john, signal_socket(client, NURSE, "nurse") as nurse:
        john.send_json({"type": "invite", "callId": str(uuid.uuid4()), "to": to})
        error = next_of_error(john)
        assert "Request a callback" in error or error == "Invalid message"  # "nurses" isn't an ID
        # Nothing rings for the nurse; she can still call John.
        call_id = str(uuid.uuid4())
        nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN)})
        assert next_of(nurse, "ringing")["callId"] == call_id


def test_strangers_cannot_join_or_answer_a_call(client):
    call_id = str(uuid.uuid4())
    with (
        signal_socket(client, NURSE, "nurse") as nurse,
        signal_socket(client, JOHN, "patient") as john,
        signal_socket(client, JANE, "patient") as jane,
    ):
        nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN)})
        next_of(john, "incoming")
        jane.send_json({"type": "accept", "callId": call_id})
        assert "isn't ringing for you" in next_of_error(jane)
        john.send_json({"type": "accept", "callId": call_id})
        next_of(nurse, "accepted")
        jane.send_json({"type": "signal", "callId": call_id, "data": {"sdp": "x"}})
        assert "not on this call" in next_of_error(jane)


def test_declined_call_is_recorded(client):
    esc = request_callback(client)
    call_id = str(uuid.uuid4())
    with signal_socket(client, NURSE, "nurse") as nurse, signal_socket(client, JOHN, "patient") as john:
        nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN)})  # case attached automatically
        next_of(john, "incoming")
        john.send_json({"type": "decline", "callId": call_id})
        assert next_of(nurse, "ended")["reason"] == "declined"
    assert case(client, esc["id"])["timeline"][-1]["outcome"] == "declined"


def test_busy_patient_cannot_be_rung_twice(client):
    with (
        signal_socket(client, NURSE, "nurse") as nurse,
        signal_socket(client, DOCTOR, "doctor") as doctor,
        signal_socket(client, JOHN, "patient") as john,
    ):
        nurse.send_json({"type": "invite", "callId": str(uuid.uuid4()), "to": str(JOHN)})
        next_of(john, "incoming")
        second = str(uuid.uuid4())
        doctor.send_json({"type": "invite", "callId": second, "to": str(JOHN)})
        assert next_of(doctor, "busy")["callId"] == second


def test_hanging_up_disconnects_the_other_side(client):
    call_id = str(uuid.uuid4())
    with signal_socket(client, NURSE, "nurse") as nurse:
        with signal_socket(client, JOHN, "patient") as john:
            nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN)})
            next_of(john, "incoming")
            john.send_json({"type": "accept", "callId": call_id})
            next_of(nurse, "accepted")
        # John's app closed mid-call: the nurse is told the call ended.
        assert next_of(nurse, "ended")["reason"] == "ended"


@pytest.fixture
def quick_ring_client(settings):
    with TestClient(create_app(settings.model_copy(update={"call_ring_seconds": 1}))) as c:
        yield c


def test_unanswered_call_is_recorded_as_missed(quick_ring_client):
    client = quick_ring_client
    esc = request_callback(client)
    call_id = str(uuid.uuid4())
    with signal_socket(client, NURSE, "nurse") as nurse, signal_socket(client, JOHN, "patient") as john:
        nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN)})
        next_of(john, "incoming")
        assert next_of(nurse, "ended")["reason"] == "missed"
        assert next_of(john, "ended")["reason"] == "missed"
    call = case(client, esc["id"])["timeline"][-1]
    assert call["action"] == "call" and call["outcome"] == "missed"


def test_invalid_messages_are_rejected_without_dropping_the_connection(client):
    with signal_socket(client, NURSE, "nurse") as nurse:
        nurse.send_text("not json")
        assert nurse.receive_json()["type"] == "error"
        nurse.send_json({"type": "invite", "callId": "nope", "to": str(JOHN)})
        assert nurse.receive_json()["type"] == "error"
        nurse.send_json({"type": "teleport"})
        assert nurse.receive_json()["type"] == "error"
        nurse.send_json({"type": "invite", "callId": str(uuid.uuid4()), "to": str(JOHN)})
        next_of(nurse, "ringing")  # still connected and working


def next_of_error(ws) -> str:
    while True:
        msg = ws.receive_json()
        if msg["type"] == "error":
            return msg["message"]


def test_reconnecting_while_ringing_delivers_the_call(client):
    call_id = str(uuid.uuid4())
    with client.websocket_connect(f"/calls/signal?token={token(NURSE, 'nurse')}") as nurse:
        nurse.send_json({"type": "invite", "callId": call_id, "to": str(JOHN)})
        while nurse.receive_json()["type"] != "ringing":
            pass
        # John's app was offline (e.g. a network drop) and connects now.
        with client.websocket_connect(f"/calls/signal?token={token(JOHN, 'patient')}") as john:
            incoming = john.receive_json()
            assert incoming["type"] == "incoming" and incoming["callId"] == call_id
            assert incoming["from"]["role"] == "nurse"
            john.send_json({"type": "accept", "callId": call_id})
            while nurse.receive_json()["type"] != "accepted":
                pass
