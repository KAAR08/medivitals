import uuid

from fastapi import APIRouter, HTTPException, Response, status

from .. import service
from ..auth import CareTeam, CurrentUser
from ..db import EscalationRecord
from ..deps import CipherDep, HubDep, Session
from ..schemas import EscalationCreate, EscalationStatus, EscalationUpdate

router = APIRouter(prefix="/escalations", tags=["escalations"])


@router.post("", status_code=status.HTTP_201_CREATED)
async def request_callback(
    body: EscalationCreate,
    user: CurrentUser,
    session: Session,
    cipher: CipherDep,
    hub: HubDep,
    response: Response,
):
    """Single-tap escalation: ask the triage nurse to call this patient back.

    Idempotent while a request is open: returns it with 200 instead of
    creating a duplicate.
    """
    if not user.can_view(body.patient_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You can only request a callback for yourself")
    severity, alerts = await service.latest_triage(session, cipher, body.patient_id)
    record, created = await service.raise_escalation(
        session,
        cipher,
        hub,
        patient_id=body.patient_id,
        source=body.source,
        severity=severity,
        alerts=alerts,
        note=body.note,
        requested_by=user.user_id,
    )
    if not created:
        response.status_code = status.HTTP_200_OK
    return service.escalation_json(record, cipher)


@router.get("")
async def list_escalations(user: CurrentUser, session: Session, cipher: CipherDep):
    """Open requests plus those resolved in the last day. Patients see only their own."""
    scope = None if user.is_care_team else user.user_id
    records = await service.visible_escalations(session, scope)
    return {"escalations": [service.escalation_json(r, cipher) for r in records]}


@router.patch("/{escalation_id}")
async def update(
    escalation_id: uuid.UUID,
    body: EscalationUpdate,
    user: CareTeam,
    session: Session,
    cipher: CipherDep,
    hub: HubDep,
):
    """Care team: take the case, resolve it, refer it to a doctor, or dispatch an ambulance."""
    record = await session.get(EscalationRecord, escalation_id)
    if record is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Escalation not found")
    try:
        record = await service.update_escalation(
            session,
            cipher,
            hub,
            record,
            EscalationStatus(body.status),
            user.user_id,
            user.role.value,
            body.note,
        )
    except service.InvalidTransition as e:
        raise HTTPException(status.HTTP_409_CONFLICT, str(e)) from None
    return service.escalation_json(record, cipher)
