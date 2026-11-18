import time
import uuid

from fastapi import APIRouter, HTTPException, Query, Request, status

from .. import service
from ..auth import CurrentUser, Device
from ..deps import CipherDep, HubDep, Session
from ..schemas import TelemetryIn

router = APIRouter(tags=["vitals"])


@router.post("/telemetry", status_code=status.HTTP_202_ACCEPTED)
async def ingest(
    reading: TelemetryIn, _: Device, request: Request, session: Session, cipher: CipherDep, hub: HubDep
):
    """Ingest one reading: validate → triage (thresholds + trends) → encrypt & store → broadcast."""
    started = time.perf_counter()
    event = await service.ingest(
        session, cipher, hub, reading, request.app.state.trends, request.app.state.latch
    )
    return {
        "accepted": True,
        "severity": event["severity"],
        "processingMs": round((time.perf_counter() - started) * 1000, 2),
    }


@router.get("/vitals/{patient_id}/history")
async def history(
    patient_id: uuid.UUID,
    user: CurrentUser,
    session: Session,
    cipher: CipherDep,
    limit: int = Query(60, ge=1, le=500),
):
    if not user.can_view(patient_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not your record")
    vitals = await service.history(session, cipher, patient_id, limit)
    return {"vitals": vitals, "total": len(vitals)}
