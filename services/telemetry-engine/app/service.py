"""Ingestion (triage, trends, encrypted storage, broadcast) and escalations."""

import logging
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from . import hub as channels
from .crypto import Cipher
from .db import EscalationRecord, VitalsRecord, utc
from .hub import Hub
from .latch import StatusLatch
from .schemas import EscalationSource, EscalationStatus, TelemetryIn, iso
from .trends import TrendTracker
from .triage import Severity, evaluate

log = logging.getLogger("engine.pipeline")


def vitals_json(
    patient_id: uuid.UUID, recorded_at: datetime, severity: str, values: dict[str, Any]
) -> dict[str, Any]:
    return {
        "patientId": str(patient_id),
        "heartRate": values["heartRate"],
        "spo2": values["spo2"],
        "systolicBP": values["systolicBP"],
        "diastolicBP": values["diastolicBP"],
        "timestamp": iso(recorded_at),
        "severity": severity,
        "alerts": values["alerts"],
    }


async def ingest(
    session: AsyncSession,
    cipher: Cipher,
    hub: Hub,
    reading: TelemetryIn,
    trends: TrendTracker,
    latch: StatusLatch,
) -> dict[str, Any]:
    triage = evaluate(reading.heart_rate, reading.spo2, reading.systolic_bp)
    drifts = trends.add(
        reading.patient_id, reading.timestamp, reading.heart_rate, reading.spo2, reading.systolic_bp
    )
    severity = triage.severity
    if drifts and severity == Severity.STABLE:
        severity = Severity.WARNING  # still "normal", but heading the wrong way
    alerts = triage.alerts + [d.alert for d in drifts]
    severity, held = latch.update(reading.patient_id, reading.timestamp, severity)
    if held:
        alerts.append("Back in range: holding this status for a minute to confirm")
    values = {
        "heartRate": reading.heart_rate,
        "spo2": reading.spo2,
        "systolicBP": reading.systolic_bp,
        "diastolicBP": reading.diastolic_bp,
        "alerts": alerts,
    }
    session.add(
        VitalsRecord(
            patient_id=reading.patient_id,
            recorded_at=reading.timestamp,
            received_at=datetime.now(UTC),
            severity=severity.value,
            payload=cipher.encrypt(values, str(reading.patient_id)),
        )
    )
    await session.commit()

    event = vitals_json(reading.patient_id, reading.timestamp, severity.value, values)
    await hub.publish(channels.VITALS, event)

    if severity == Severity.CRITICAL:
        note = "Automatic: critical reading"
    elif len(drifts) >= 2:
        note = "Early warning: several vitals deteriorating together"
    else:
        note = None
    if note:
        await raise_escalation(
            session,
            cipher,
            hub,
            patient_id=reading.patient_id,
            source=EscalationSource.AUTO,
            severity=severity,
            alerts=alerts,
            note=note,
        )
    return event


async def history(
    session: AsyncSession, cipher: Cipher, patient_id: uuid.UUID, limit: int
) -> list[dict[str, Any]]:
    rows = (
        await session.scalars(
            select(VitalsRecord)
            .where(VitalsRecord.patient_id == patient_id)
            .order_by(VitalsRecord.recorded_at.desc())
            .limit(limit)
        )
    ).all()
    return [
        vitals_json(
            r.patient_id, utc(r.recorded_at), r.severity, cipher.decrypt(r.payload, str(r.patient_id))
        )
        for r in reversed(rows)  # oldest first, as the app's charts expect
    ]


async def latest_triage(
    session: AsyncSession, cipher: Cipher, patient_id: uuid.UUID
) -> tuple[Severity, list[str]]:
    row = await session.scalar(
        select(VitalsRecord)
        .where(VitalsRecord.patient_id == patient_id)
        .order_by(VitalsRecord.recorded_at.desc())
        .limit(1)
    )
    if row is None:
        return Severity.STABLE, []
    return Severity(row.severity), cipher.decrypt(row.payload, str(row.patient_id))["alerts"]


def escalation_json(record: EscalationRecord, cipher: Cipher) -> dict[str, Any]:
    sealed = cipher.decrypt(record.payload, str(record.patient_id))
    data: dict[str, Any] = {
        "id": str(record.id),
        "patientId": str(record.patient_id),
        "source": record.source,
        "status": record.status,
        "severity": record.severity,
        "alerts": sealed["alerts"],
        "createdAt": iso(utc(record.created_at)),
    }
    if sealed.get("note"):
        data["note"] = sealed["note"]
    data["timeline"] = sealed.get("timeline", [])
    if record.acknowledged_by:
        data["acknowledgedBy"] = str(record.acknowledged_by)
    if record.acknowledged_at:
        data["acknowledgedAt"] = iso(utc(record.acknowledged_at))
    if record.resolved_at:
        data["resolvedAt"] = iso(utc(record.resolved_at))
    return data


async def open_escalation(session: AsyncSession, patient_id: uuid.UUID) -> EscalationRecord | None:
    return await session.scalar(
        select(EscalationRecord).where(
            EscalationRecord.patient_id == patient_id,
            EscalationRecord.status != EscalationStatus.RESOLVED.value,
        )
    )


async def raise_escalation(
    session: AsyncSession,
    cipher: Cipher,
    hub: Hub,
    *,
    patient_id: uuid.UUID,
    source: EscalationSource,
    severity: Severity,
    alerts: list[str],
    note: str | None = None,
    requested_by: uuid.UUID | None = None,
) -> tuple[EscalationRecord, bool]:
    """Creates a callback request unless one is already open.

    Returns (escalation, created). At most one open request per patient is
    enforced by a partial unique index, so concurrent critical readings
    cannot raise duplicates.
    """
    existing = await open_escalation(session, patient_id)
    if existing:
        return existing, False

    record = EscalationRecord(
        id=uuid.uuid4(),
        patient_id=patient_id,
        source=source.value,
        status=EscalationStatus.PENDING.value,
        severity=severity.value,
        created_at=datetime.now(UTC),
        requested_by=requested_by,
        payload=cipher.encrypt(
            {
                "alerts": alerts,
                "note": note,
                "timeline": [_event("raised", requested_by, source.value, note)],
            },
            str(patient_id),
        ),
    )
    session.add(record)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        existing = await open_escalation(session, patient_id)
        if existing is None:
            raise
        return existing, False

    log.info("Escalation %s raised for patient %s (%s)", record.id, patient_id, source.value)
    await hub.publish(channels.ESCALATIONS, {"type": "escalation", **escalation_json(record, cipher)})
    return record, True


# Where a case can go next. A nurse calls the patient (acknowledged), then
# either resolves it, refers it to a doctor, or dispatches an ambulance.
_S = EscalationStatus
_TRANSITIONS = {
    _S.PENDING: {_S.ACKNOWLEDGED, _S.REFERRED, _S.AMBULANCE, _S.RESOLVED},
    _S.ACKNOWLEDGED: {_S.REFERRED, _S.AMBULANCE, _S.RESOLVED},
    _S.REFERRED: {_S.ACKNOWLEDGED, _S.AMBULANCE, _S.RESOLVED},
    _S.AMBULANCE: {_S.RESOLVED},
    _S.RESOLVED: set(),
}


class InvalidTransition(Exception):
    pass


def _event(action: str, actor: uuid.UUID | None, role: str, note: str | None = None, **extra: Any):
    event: dict[str, Any] = {"at": iso(datetime.now(UTC)), "action": action, "role": role}
    if actor:
        event["by"] = str(actor)
    if note:
        event["note"] = note
    event.update(extra)
    return event


async def _append(session: AsyncSession, cipher: Cipher, hub: Hub, record: EscalationRecord, event) -> None:
    """Adds an entry to the case's encrypted timeline and broadcasts the change."""
    sealed = cipher.decrypt(record.payload, str(record.patient_id))
    sealed.setdefault("timeline", []).append(event)
    record.payload = cipher.encrypt(sealed, str(record.patient_id))
    await session.commit()
    await hub.publish(channels.ESCALATIONS, {"type": "escalation", **escalation_json(record, cipher)})


async def update_escalation(
    session: AsyncSession,
    cipher: Cipher,
    hub: Hub,
    record: EscalationRecord,
    new_status: EscalationStatus,
    actor: uuid.UUID,
    role: str,
    note: str | None = None,
) -> EscalationRecord:
    current = EscalationStatus(record.status)
    if new_status not in _TRANSITIONS[current]:
        raise InvalidTransition(f"Cannot move an escalation from {current} to {new_status}")
    now = datetime.now(UTC)
    record.status = new_status.value
    if new_status == EscalationStatus.ACKNOWLEDGED or record.acknowledged_by is None:
        record.acknowledged_by, record.acknowledged_at = actor, now
    if new_status == EscalationStatus.RESOLVED:
        record.resolved_at = now
    log.info("Escalation %s -> %s by %s", record.id, new_status.value, role)
    await _append(session, cipher, hub, record, _event(new_status.value, actor, role, note))
    return record


async def record_call(
    session: AsyncSession,
    cipher: Cipher,
    hub: Hub,
    escalation_id: uuid.UUID,
    *,
    outcome: str,
    caller: uuid.UUID,
    caller_role: str,
    seconds: int,
    video: bool,
) -> None:
    """Notes a finished (or missed) call on the case's timeline."""
    record = await session.get(EscalationRecord, escalation_id)
    if record is not None:
        event = _event("call", caller, caller_role, outcome=outcome, seconds=seconds, video=video)
        await _append(session, cipher, hub, record, event)


async def visible_escalations(
    session: AsyncSession, patient_scope: uuid.UUID | None
) -> list[EscalationRecord]:
    """Open requests plus those resolved in the last 24 h, for one patient or the whole ward."""
    recent = datetime.now(UTC) - timedelta(hours=24)
    query = select(EscalationRecord).where(
        (EscalationRecord.status != EscalationStatus.RESOLVED.value)
        | (EscalationRecord.resolved_at >= recent)
    )
    if patient_scope is not None:
        query = query.where(EscalationRecord.patient_id == patient_scope)
    return list((await session.scalars(query.order_by(EscalationRecord.created_at))).all())
