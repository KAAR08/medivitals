"""Voice and video calls between patients and the care team.

The engine is the signalling server only: it decides who may ring whom,
relays WebRTC session descriptions and ICE candidates between the two people
on a call, and keeps a record (who, when, how long). Audio and video flow
directly between the devices, encrypted end to end by WebRTC (DTLS-SRTP), or
through the TURN relay when a direct path is impossible.

Rules:
- Only the care team starts calls: a nurse or doctor may call any patient on
  the ward. If the patient has an open case, the call is attached to it and
  the case is taken ("acknowledged").
- Patients can't start calls. They request a callback and the triage nurse
  calls them when she is free, so nurses aren't interrupted mid-consultation.
- Session data (SDP, ICE) is only relayed between the two parties of an
  answered call.
"""

import asyncio
import base64
import hashlib
import hmac
import logging
import time
import uuid
from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from . import hub as channels
from . import service
from .auth import Principal, Role
from .config import Settings
from .crypto import Cipher
from .db import CallRecord, EscalationRecord, utc
from .hub import Hub
from .schemas import EscalationStatus

log = logging.getLogger("engine.calls")

_LIVE = ("ringing", "active")
_MAX_SIGNAL_BYTES = 64 * 1024


class _Msg(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class Invite(_Msg):
    type: Literal["invite"]
    call_id: uuid.UUID = Field(alias="callId")
    to: uuid.UUID  # the patient
    escalation_id: uuid.UUID | None = Field(default=None, alias="escalationId")
    video: bool = False


class CallAction(_Msg):
    type: Literal["accept", "decline", "hangup"]
    call_id: uuid.UUID = Field(alias="callId")


class Signal(_Msg):
    type: Literal["signal"]
    call_id: uuid.UUID = Field(alias="callId")
    data: dict[str, Any]


class Media(_Msg):
    type: Literal["media"]
    call_id: uuid.UUID = Field(alias="callId")
    video: bool


_PARSERS: dict[str, type[_Msg]] = {
    "invite": Invite,
    "accept": CallAction,
    "decline": CallAction,
    "hangup": CallAction,
    "signal": Signal,
    "media": Media,
}


class CallError(Exception):
    """Reported to the sender as {"type": "error"}; never fatal to the socket."""

    def __init__(self, message: str, call_id: uuid.UUID | None = None) -> None:
        super().__init__(message)
        self.call_id = call_id


def parse(raw: dict[str, Any]) -> _Msg:
    parser = _PARSERS.get(raw.get("type", ""))
    if parser is None:
        raise CallError("Unknown message type")
    try:
        return parser.model_validate(raw)
    except ValidationError:
        raise CallError("Invalid message", _call_id(raw)) from None


def _call_id(raw: dict[str, Any]) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(raw.get("callId")))
    except ValueError:
        return None


def ice_servers(settings: Settings, user: Principal) -> dict[str, Any]:
    """STUN/TURN servers for this user, with time-limited TURN credentials.

    coturn's REST-API scheme: username = "<expiry>:<user>", password =
    base64(HMAC-SHA1(secret, username)). coturn checks both without a database,
    and a leaked credential expires on its own.
    """
    servers: list[dict[str, Any]] = []
    if settings.stun_urls:
        servers.append({"urls": settings.stun_urls})
    if settings.turn_urls and settings.turn_secret:
        username = f"{int(time.time()) + settings.turn_ttl_seconds}:{user.user_id}"
        digest = hmac.new(settings.turn_secret.encode(), username.encode(), hashlib.sha1).digest()
        servers.append(
            {
                "urls": settings.turn_urls,
                "username": username,
                "credential": base64.b64encode(digest).decode(),
            }
        )
    return {"iceServers": servers, "ttl": settings.turn_ttl_seconds}


def _incoming(call: CallRecord) -> dict[str, Any]:
    return {
        "type": "incoming",
        **call_json(call),
        "from": {"id": str(call.caller_id), "role": call.caller_role},
    }


def call_json(call: CallRecord) -> dict[str, Any]:
    return {
        "callId": str(call.id),
        "patientId": str(call.patient_id),
        "escalationId": str(call.escalation_id) if call.escalation_id else None,
        "video": call.video,
    }


class Calls:
    def __init__(
        self,
        sessions: async_sessionmaker[AsyncSession],
        hub: Hub,
        cipher: Cipher,
        settings: Settings,
    ) -> None:
        self._sessions = sessions
        self._hub = hub
        self._cipher = cipher
        self._ring_seconds = settings.call_ring_seconds
        self._timers: set[asyncio.Task[None]] = set()

    # -- delivery ------------------------------------------------------------

    async def send(self, to: uuid.UUID | str, message: dict[str, Any]) -> None:
        await self._hub.publish(channels.CALLS, {"to": str(to), "msg": message})

    @staticmethod
    def addressed_to(user: Principal, envelope: dict[str, Any]) -> bool:
        return envelope.get("to") == str(user.user_id)

    # -- entry point ---------------------------------------------------------

    async def handle(self, user: Principal, raw: dict[str, Any]) -> None:
        msg = parse(raw)
        async with self._sessions() as session:
            match msg:
                case Invite():
                    await self._invite(session, user, msg)
                case CallAction(type="accept"):
                    await self._accept(session, user, msg.call_id)
                case CallAction(type="decline"):
                    await self._decline(session, user, msg.call_id)
                case CallAction(type="hangup"):
                    await self._hangup(session, user, msg.call_id)
                case Signal():
                    await self._relay(session, user, msg)
                case Media():
                    await self._media(session, user, msg)

    # -- invite --------------------------------------------------------------

    async def _invite(self, session: AsyncSession, user: Principal, msg: Invite) -> None:
        if await session.get(CallRecord, msg.call_id) is not None:
            raise CallError("Call ID already used", msg.call_id)

        if not user.is_care_team:
            raise CallError("Request a callback: the triage nurse will call you", msg.call_id)
        patient_id = msg.to
        escalation = await self._case_for(session, patient_id, msg.escalation_id, msg.call_id)

        if await self._busy(session, user.user_id) or await self._busy(session, patient_id):
            await self.send(user.user_id, {"type": "busy", "callId": str(msg.call_id)})
            return

        call = CallRecord(
            id=msg.call_id,
            patient_id=patient_id,
            escalation_id=escalation.id if escalation else None,
            caller_id=user.user_id,
            caller_role=user.role.value,
            callee_id=patient_id,
            callee_role=Role.PATIENT.value,
            status="ringing",
            video=msg.video,
            created_at=datetime.now(UTC),
        )
        session.add(call)
        await session.commit()

        # Calling the patient about their case means the case is being handled.
        if escalation and escalation.status in ("pending", "referred"):
            await service.update_escalation(
                session,
                self._cipher,
                self._hub,
                escalation,
                EscalationStatus.ACKNOWLEDGED,
                user.user_id,
                user.role.value,
            )

        log.info("Call %s: %s -> patient", call.id, user.role.value)
        await self.send(patient_id, _incoming(call))
        await self.send(user.user_id, {"type": "ringing", **call_json(call)})
        self._start_ring_timer(call.id)

    async def redeliver(self, user: Principal) -> None:
        """The patient's app (re)connected while a call is ringing for them,
        e.g. after a network drop: ring it again."""
        async with self._sessions() as session:
            ringing = (
                await session.scalars(
                    select(CallRecord).where(
                        CallRecord.callee_id == user.user_id, CallRecord.status == "ringing"
                    )
                )
            ).all()
        for call in ringing:
            await self.send(user.user_id, _incoming(call))

    def _background(self, work) -> None:
        task = asyncio.create_task(work)
        self._timers.add(task)
        task.add_done_callback(self._timers.discard)

    async def _case_for(
        self,
        session: AsyncSession,
        patient_id: uuid.UUID,
        escalation_id: uuid.UUID | None,
        call_id: uuid.UUID,
    ) -> EscalationRecord | None:
        if escalation_id is None:
            return await service.open_escalation(session, patient_id)
        record = await session.get(EscalationRecord, escalation_id)
        if record is None or record.patient_id != patient_id:
            raise CallError("That case doesn't belong to this patient", call_id)
        if record.status == EscalationStatus.RESOLVED.value:
            raise CallError("That case is already resolved", call_id)
        return record

    async def _busy(self, session: AsyncSession, user_id: uuid.UUID) -> bool:
        return (
            await session.scalar(
                select(CallRecord.id)
                .where(CallRecord.status.in_(_LIVE))
                .where((CallRecord.caller_id == user_id) | (CallRecord.callee_id == user_id))
                .limit(1)
            )
        ) is not None

    # -- answer / decline / hang up ------------------------------------------

    async def _accept(self, session: AsyncSession, user: Principal, call_id: uuid.UUID) -> None:
        call = await self._call(session, call_id)
        if call.callee_id != user.user_id or call.status != "ringing":
            raise CallError("This call isn't ringing for you", call_id)
        call.status, call.answered_at = "active", datetime.now(UTC)
        await session.commit()

        accepted = {
            "type": "accepted",
            **call_json(call),
            "by": {"id": str(user.user_id), "role": user.role.value},
        }
        await self.send(call.caller_id, accepted)
        await self.send(user.user_id, accepted)

    async def _decline(self, session: AsyncSession, user: Principal, call_id: uuid.UUID) -> None:
        call = await self._call(session, call_id)
        if call.callee_id != user.user_id or call.status != "ringing":
            raise CallError("This call isn't ringing for you", call_id)
        await self._finish(session, call, "declined", notify=[call.caller_id])

    async def _hangup(self, session: AsyncSession, user: Principal, call_id: uuid.UUID) -> None:
        call = await self._call(session, call_id)
        if user.user_id not in (call.caller_id, call.callee_id):
            raise CallError("You're not on this call", call_id)
        if call.status not in _LIVE:
            return
        other = call.callee_id if user.user_id == call.caller_id else call.caller_id
        status = "ended" if call.status == "active" else "cancelled"
        await self._finish(session, call, status, notify=[other])

    async def _finish(
        self, session: AsyncSession, call: CallRecord, status: str, notify: list[uuid.UUID | None]
    ) -> None:
        answered = call.status == "active"
        call.status, call.ended_at = status, datetime.now(UTC)
        await session.commit()
        seconds = (
            int((call.ended_at - utc(call.answered_at)).total_seconds())
            if answered and call.answered_at
            else 0
        )
        log.info("Call %s %s after %d s", call.id, status, seconds)
        if call.escalation_id:
            await service.record_call(
                session,
                self._cipher,
                self._hub,
                call.escalation_id,
                outcome="answered" if answered else status,
                caller=call.caller_id,
                caller_role=call.caller_role,
                seconds=seconds,
                video=call.video,
            )

        # Records first, so the case is up to date when the parties hear about it.
        for party in notify:
            if party is not None:
                await self.send(party, {"type": "ended", "callId": str(call.id), "reason": status})

    # -- in-call messages ----------------------------------------------------

    async def _relay(self, session: AsyncSession, user: Principal, msg: Signal) -> None:
        call = await self._active_call_for(session, user, msg.call_id)
        if len(str(msg.data)) > _MAX_SIGNAL_BYTES:
            raise CallError("Signal too large", msg.call_id)
        await self.send(self._other(call, user), {"type": "signal", "callId": str(call.id), "data": msg.data})

    async def _media(self, session: AsyncSession, user: Principal, msg: Media) -> None:
        call = await self._active_call_for(session, user, msg.call_id)
        if msg.video and not call.video:
            call.video = True
            await session.commit()
        await self.send(
            self._other(call, user), {"type": "media", "callId": str(call.id), "video": msg.video}
        )

    async def _call(self, session: AsyncSession, call_id: uuid.UUID) -> CallRecord:
        call = await session.get(CallRecord, call_id)
        if call is None:
            raise CallError("Unknown call", call_id)
        return call

    async def _active_call_for(
        self, session: AsyncSession, user: Principal, call_id: uuid.UUID
    ) -> CallRecord:
        call = await self._call(session, call_id)
        if call.status != "active" or user.user_id not in (call.caller_id, call.callee_id):
            raise CallError("You're not on this call", call_id)
        return call

    @staticmethod
    def _other(call: CallRecord, user: Principal) -> uuid.UUID:
        other = call.callee_id if user.user_id == call.caller_id else call.caller_id
        assert other is not None  # noqa: S101 - an active call always has both parties
        return other

    # -- timeouts and disconnects --------------------------------------------

    def _start_ring_timer(self, call_id: uuid.UUID) -> None:
        self._background(self._ring_timeout(call_id))

    async def _ring_timeout(self, call_id: uuid.UUID) -> None:
        await asyncio.sleep(self._ring_seconds)
        try:
            async with self._sessions() as session:
                call = await session.get(CallRecord, call_id)
                if call is not None and call.status == "ringing":
                    await self._finish(session, call, "missed", notify=[call.caller_id, call.callee_id])
        except Exception:  # noqa: BLE001 - a timer must never crash the server
            log.exception("Ring timeout for call %s failed", call_id)

    async def disconnected(self, user: Principal) -> None:
        """The user's last connection closed: end their live calls."""
        async with self._sessions() as session:
            calls = (
                await session.scalars(
                    select(CallRecord)
                    .where(CallRecord.status.in_(_LIVE))
                    .where((CallRecord.caller_id == user.user_id) | (CallRecord.callee_id == user.user_id))
                )
            ).all()
            for call in calls:
                other = call.callee_id if user.user_id == call.caller_id else call.caller_id
                status = "ended" if call.status == "active" else "missed"
                await self._finish(session, call, status, notify=[other])

    async def stop(self) -> None:
        for task in list(self._timers):
            task.cancel()
