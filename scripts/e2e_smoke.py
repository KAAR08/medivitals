"""End-to-end acceptance test of the running system, through the gateway only.

Checks the running system the way the app uses it: TLS 1.3
only, logins for every role, role-based access, pseudonymized live streams,
end-to-end latency under 2 s, single-tap escalation to the triage nurse, and
automatic escalation of critical readings.

    docker compose up -d && python scripts/export_dev_ca.py
    python scripts/e2e_smoke.py                          # local stack
    python scripts/e2e_smoke.py https://api.example.org  # deployed (public CA)

Needs httpx and websockets (both in the telemetry engine's dev requirements).
Logs in 6 times, so mind the login rate limit (10 per 15 minutes per IP).
"""

import asyncio
import hashlib
import hmac
import json
import os
import socket
import ssl
import statistics
import struct
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

import httpx
import websockets

ROOT = Path(__file__).resolve().parent.parent
BASE = (sys.argv[1] if len(sys.argv) > 1 else "https://localhost:8443").rstrip("/")
WSS = "wss" + BASE[len("https") :]
HOST, PORT = urlsplit(BASE).hostname, urlsplit(BASE).port or 443
_dev_ca = ROOT / "secrets" / "dev_ca.crt"
CA = str(_dev_ca) if HOST == "localhost" and _dev_ca.exists() else None
JOHN, BOB = "7c9e6679-7425-40de-944b-e07fc1f90ae7", "9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d"
# Each account's own password (scripts/generate_dev_secrets.py; ACCOUNTS_FILE overrides).
_accounts = json.loads(
    Path(os.environ.get("ACCOUNTS_FILE", ROOT / "secrets" / "accounts.json")).read_text(encoding="utf-8")
)
_first = lambda pred: next(a for a in _accounts if pred(a))  # noqa: E731
LOGINS = {
    "doctor": _first(lambda a: a["role"] == "doctor"),
    "nurse": _first(lambda a: a["role"] == "nurse"),
    "patient": _first(lambda a: a.get("id") == JOHN),
    "bob": _first(lambda a: a.get("id") == BOB),
}
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {detail}")


def tls_probe() -> None:
    ctx = ssl.create_default_context(cafile=CA)
    with socket.create_connection((HOST, PORT)) as s, ctx.wrap_socket(s, server_hostname=HOST) as t:
        check("TLS 1.3 negotiated, certificate valid", t.version() == "TLSv1.3", t.version())
    ctx12 = ssl.create_default_context(cafile=CA)
    ctx12.maximum_version = ssl.TLSVersion.TLSv1_2
    try:
        with socket.create_connection((HOST, PORT)) as s, ctx12.wrap_socket(s, server_hostname=HOST):
            check("TLS 1.2 refused", False, "handshake succeeded")
    except ssl.SSLError as e:
        check("TLS 1.2 refused", True, type(e).__name__)


async def check_calls(c: httpx.AsyncClient, tokens: dict, H, case_id: str) -> None:
    r = await c.get("/calls/ice-servers", headers=H("patient"))
    servers = r.json().get("iceServers", [])
    turn = next((s for s in servers if "username" in s), None)
    check(
        "ICE servers include TURN with short-lived credentials", turn is not None, f"{len(servers)} servers"
    )

    ctx = ssl.create_default_context(cafile=CA)
    call_id = str(uuid.uuid4())

    async def next_of(ws, kind: str) -> dict:
        while True:
            msg = json.loads(await asyncio.wait_for(ws.recv(), 10))
            if msg["type"] in (kind, "error"):
                return msg

    async with (
        websockets.connect(f"{WSS}/calls/signal?token={tokens['nurse']}", ssl=ctx) as nurse,
        websockets.connect(f"{WSS}/calls/signal?token={tokens['patient']}", ssl=ctx) as john,
    ):
        # Patients request a callback; they can't ring the nurses.
        await john.send(json.dumps({"type": "invite", "callId": str(uuid.uuid4()), "to": BOB}))
        refused = await next_of(john, "error")
        check("patient can't start a call", refused.get("type") == "error", refused.get("message", ""))
        await nurse.send(
            json.dumps({"type": "invite", "callId": call_id, "to": JOHN, "escalationId": case_id})
        )
        incoming = await next_of(john, "incoming")
        check(
            "call rings the patient through the gateway", incoming.get("type") == "incoming", incoming["type"]
        )
        await john.send(json.dumps({"type": "accept", "callId": call_id}))
        accepted = await next_of(nurse, "accepted")
        check("patient answers", accepted.get("type") == "accepted")
        await nurse.send(
            json.dumps({"type": "signal", "callId": call_id, "data": {"sdp": "e2e", "sdpType": "offer"}})
        )
        relayed = await next_of(john, "signal")
        check("WebRTC offer relayed to the patient", relayed.get("data", {}).get("sdp") == "e2e")
        await john.send(json.dumps({"type": "hangup", "callId": call_id}))
        ended = await next_of(nurse, "ended")
        check(
            "hang-up reaches the nurse",
            ended.get("reason") == "ended",
            ended.get("reason", ended.get("message")),
        )

    r = await c.get("/escalations", headers=H("nurse"))
    case = next(e for e in r.json()["escalations"] if e["id"] == case_id)
    check("call recorded on the case timeline", case["timeline"][-1].get("action") == "call")

    if turn:
        url = urlsplit(turn["urls"][0].replace("turn:", "turn://"))
        host = "127.0.0.1" if url.hostname == "localhost" else url.hostname
        ok, detail = turn_allocate(host, url.port or 3478, turn["username"], turn["credential"])
        check("TURN relay allocates with engine-issued credentials", ok, detail)
        ok, detail = turn_allocate(host, url.port or 3478, turn["username"], "forged-password")
        check("TURN relay rejects a forged credential", not ok, detail)


def turn_allocate(host: str, port: int, username: str, password: str) -> tuple[bool, str]:
    """Minimal TURN (RFC 5766) Allocate over UDP with long-term credentials."""

    def attr(kind: int, value: bytes) -> bytes:
        return struct.pack("!HH", kind, len(value)) + value + b"\0" * (-len(value) % 4)

    def message(kind: int, attrs: bytes, txid: bytes, key: bytes | None = None) -> bytes:
        if key is None:
            return struct.pack("!HHI", kind, len(attrs), 0x2112A442) + txid + attrs
        header = struct.pack("!HHI", kind, len(attrs) + 24, 0x2112A442) + txid
        mac = hmac.new(key, header + attrs, hashlib.sha1).digest()
        return header + attrs + attr(0x0008, mac)

    def parse(data: bytes) -> tuple[int, dict[int, bytes]]:
        kind, length = struct.unpack("!HH", data[:4])
        attrs, i = {}, 20
        while i < 20 + length:
            t, n = struct.unpack("!HH", data[i : i + 4])
            attrs[t] = data[i + 4 : i + 4 + n]
            i += 4 + n + (-n % 4)
        return kind, attrs

    transport = attr(0x0019, bytes([17, 0, 0, 0]))  # UDP relay
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(3)
        try:
            s.sendto(message(0x0003, transport, os.urandom(12)), (host, port))
            kind, attrs = parse(s.recv(2048))
            if kind != 0x0113 or 0x0014 not in attrs:
                return False, f"unexpected challenge 0x{kind:04x}"
            realm, nonce = attrs[0x0014], attrs[0x0015]
            key = hashlib.md5(f"{username}:{realm.decode()}:{password}".encode()).digest()  # noqa: S324 - TURN spec
            auth = attr(0x0006, username.encode()) + attr(0x0014, realm) + attr(0x0015, nonce)
            s.sendto(message(0x0003, transport + auth, os.urandom(12), key), (host, port))
            kind, attrs = parse(s.recv(2048))
            if kind == 0x0103:
                # Release it straight away (Refresh with lifetime 0).
                s.sendto(message(0x0004, attr(0x000D, b"\0\0\0\0") + auth, os.urandom(12), key), (host, port))
                return True, "relay address allocated"
            code = attrs.get(0x0009, b"\0\0\0\0")
            return False, f"error {code[2] * 100 + code[3]}"
        except TimeoutError:
            return False, "no response (is UDP 3478 published?)"


async def main() -> None:
    tls_probe()
    async with httpx.AsyncClient(
        base_url=BASE, verify=ssl.create_default_context(cafile=CA), timeout=60
    ) as c:
        r = await c.get("/health")
        check("gateway -> engine /health", r.status_code == 200)
        check("HSTS header", "strict-transport-security" in r.headers)
        check("Server header removed", "server" not in r.headers, r.headers.get("server", ""))

        tokens, users = {}, {}
        for role, account in LOGINS.items():
            r = await c.post(
                "/auth/login",
                json={"email": account["email"], "password": account["password"], "role": account["role"]},
            )
            ok = r.status_code == 200
            check(f"login {role}", ok, "" if ok else r.text[:120])
            if ok:
                body = r.json()
                tokens[role] = body["access_token"]
                users[role] = body["user"]
        if len(tokens) < 4:
            sys.exit("login failed; cannot continue")
        H = lambda role: {"Authorization": f"Bearer {tokens[role]}"}  # noqa: E731

        r = await c.post(
            "/auth/login",
            json={"email": LOGINS["patient"]["email"], "password": "wrong-password!!", "role": "patient"},
        )
        check("wrong password -> 401", r.status_code == 401)
        r = await c.post(
            "/auth/login",
            json={"email": LOGINS["patient"]["email"], "password": LOGINS["patient"]["password"], "role": "doctor"},
        )
        check("patient logging in as doctor -> 401", r.status_code == 401)

        r = await c.get("/patients", headers=H("doctor"))
        check(
            "doctor reads directory",
            r.status_code == 200 and len(r.json()["patients"]) == 3,
            str(r.status_code),
        )
        r = await c.get("/patients", headers=H("patient"))
        check("patient denied directory", r.status_code == 403, str(r.status_code))

        r = await c.get(f"/vitals/{JOHN}/history", headers=H("patient"))
        check("patient reads own history", r.status_code == 200, str(r.status_code))
        r = await c.get(f"/vitals/{BOB}/history", headers=H("patient"))
        check("patient denied other's history", r.status_code == 403, str(r.status_code))
        r = await c.get(f"/vitals/{BOB}/history", headers=H("doctor"))
        check("doctor reads any history", r.status_code == 200, str(r.status_code))
        r = await c.get(f"/vitals/{JOHN}/history")
        check("no token -> 401", r.status_code == 401, str(r.status_code))

        # Live monitor stream: latency from generation to arrival through the gateway.
        lat, sev, ids, first = [], {}, set(), None
        async with websockets.connect(
            f"{WSS}/monitor/stream?token={tokens['doctor']}", ssl=ssl.create_default_context(cafile=CA)
        ) as ws:
            end = asyncio.get_running_loop().time() + 20
            while asyncio.get_running_loop().time() < end:
                msg = json.loads(await asyncio.wait_for(ws.recv(), 10))
                now = datetime.now(UTC)
                first = first or msg
                ts = msg.get("generated_at") or msg.get("timestamp")
                if ts:
                    lat.append((now - datetime.fromisoformat(ts.replace("Z", "+00:00"))).total_seconds())
                ids.add(msg.get("patientId"))
                sev[msg.get("severity")] = sev.get(msg.get("severity"), 0) + 1
        check("monitor stream: all 3 patients", len(ids) == 3, f"{len(ids)} ids, {len(lat)} readings")
        check("stream carries no names (pseudonymized)", "name" not in json.dumps(first).lower())
        if lat:
            p95 = sorted(lat)[int(len(lat) * 0.95) - 1]
            check(
                "latency < 2 s (max)",
                max(lat) < 2,
                f"median {statistics.median(lat) * 1000:.0f} ms, p95 {p95 * 1000:.0f} ms, "
                f"max {max(lat) * 1000:.0f} ms over {len(lat)} readings",
            )
        print("severity counts:", sev)

        try:
            async with websockets.connect(
                f"{WSS}/vitals/{BOB}/stream?token={tokens['patient']}",
                ssl=ssl.create_default_context(cafile=CA),
            ) as ws:
                await asyncio.wait_for(ws.recv(), 5)
                check("patient denied other's stream", False)
        except websockets.ConnectionClosed as e:
            check(
                "patient denied other's stream", e.rcvd and e.rcvd.code == 4403, str(e.rcvd and e.rcvd.code)
            )
        except websockets.InvalidStatus as e:
            check(
                "patient denied other's stream",
                e.response.status_code == 403,
                f"HTTP {e.response.status_code}",
            )

        # Start from a known state: close any case left open for John (e.g. by
        # manual testing), so the request below opens a new one.
        r = await c.get("/escalations", headers=H("nurse"))
        for e in r.json()["escalations"]:
            if e["patientId"] == JOHN and e["status"] != "resolved":
                await c.patch(f"/escalations/{e['id']}", headers=H("nurse"), json={"status": "resolved"})

        # Escalation: patient taps, nurse sees it live, acknowledges, resolves.
        async with websockets.connect(
            f"{WSS}/escalations/stream?token={tokens['nurse']}", ssl=ssl.create_default_context(cafile=CA)
        ) as nws:
            r = await c.post(
                "/escalations", headers=H("patient"), json={"patientId": JOHN, "source": "patient"}
            )
            check("patient requests callback", r.status_code in (200, 201), f"{r.status_code} {r.text[:160]}")
            esc = r.json()
            evt = None
            try:
                while True:
                    evt = json.loads(await asyncio.wait_for(nws.recv(), 5))
                    if json.dumps(evt).find(esc.get("id", "?")) >= 0:
                        break
            except TimeoutError:
                evt = None
            check("nurse receives it live", evt is not None)
            r2 = await c.post(
                "/escalations", headers=H("patient"), json={"patientId": JOHN, "source": "patient"}
            )
            check(
                "second tap is idempotent (200, same id)",
                r2.status_code == 200 and r2.json()["id"] == esc["id"],
            )
            r = await c.post(
                "/escalations", headers=H("patient"), json={"patientId": BOB, "source": "patient"}
            )
            check("patient can't escalate for another", r.status_code == 403, str(r.status_code))
            r = await c.patch(
                f"/escalations/{esc['id']}", headers=H("patient"), json={"status": "acknowledged"}
            )
            check("patient can't acknowledge", r.status_code == 403, str(r.status_code))
            for st in ("acknowledged", "resolved"):
                r = await c.patch(f"/escalations/{esc['id']}", headers=H("nurse"), json={"status": st})
                check(f"nurse -> {st}", r.status_code == 200, f"{r.status_code} {r.text[:120]}")

        r = await c.get("/escalations", headers=H("nurse"))
        auto = [e for e in r.json()["escalations"] if e.get("source") == "auto"]
        check(
            "critical readings auto-escalated (Bob)",
            any(e.get("patientId", e.get("patient_id")) == BOB for e in auto),
            f"{len(auto)} auto",
        )

        # Nurse can't settle it: refer to a doctor, who dispatches an ambulance.
        r = await c.post("/escalations", headers=H("patient"), json={"patientId": JOHN})
        case_id = r.json()["id"]
        r = await c.patch(
            f"/escalations/{case_id}",
            headers=H("nurse"),
            json={"status": "referred", "note": "e2e: chest pain, please review"},
        )
        check("nurse refers to doctor (with note)", r.json().get("status") == "referred")
        r = await c.patch(
            f"/escalations/{case_id}", headers=H("doctor"), json={"status": "ambulance", "note": "e2e"}
        )
        check("doctor dispatches ambulance (simulated)", r.json().get("status") == "ambulance")
        r = await c.patch(f"/escalations/{case_id}", headers=H("doctor"), json={"status": "referred"})
        check("ambulance case can't go back to referred", r.status_code == 409, str(r.status_code))

        # Calls: signalling through the gateway, TURN credentials, the relay.
        await check_calls(c, tokens, H, case_id)
        await c.patch(f"/escalations/{case_id}", headers=H("nurse"), json={"status": "resolved"})

    failed = [n for n, ok, _ in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed" + (f"; FAILED: {failed}" if failed else ""))

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
