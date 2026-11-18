"""Live WebSocket streams.

WebSocket clients can't set headers on the handshake, so the access token
comes as `?token=`. The engine runs without an access log, and the gateway
strips the parameter from its own, so tokens never reach a log.
"""

import asyncio
import contextlib
import uuid
from collections.abc import Callable
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from .. import hub as channels
from ..auth import AuthError, Principal

router = APIRouter(tags=["streams"])

_UNAUTHORIZED = 4401
_FORBIDDEN = 4403


async def authenticate(ws: WebSocket) -> Principal | None:
    token = ws.query_params.get("token")
    if not token:
        await ws.close(code=_UNAUTHORIZED, reason="Missing token")
        return None
    try:
        return await ws.app.state.verifier.verify(token)
    except AuthError:
        await ws.close(code=_UNAUTHORIZED, reason="Invalid or expired token")
        return None


async def _pump(ws: WebSocket, channel: str, accept: Callable[[dict[str, Any]], bool]) -> None:
    """Forward matching hub events until the client goes away."""
    await ws.accept()
    async with ws.app.state.hub.subscribe(channel) as queue:

        async def forward() -> None:
            while True:
                event = await queue.get()
                if accept(event):
                    await ws.send_json(event)

        async def until_closed() -> None:
            while (await ws.receive())["type"] != "websocket.disconnect":
                pass  # clients don't send anything; ignore pings/messages

        tasks = [asyncio.create_task(forward()), asyncio.create_task(until_closed())]
        _, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        with contextlib.suppress(asyncio.CancelledError, WebSocketDisconnect, RuntimeError):
            await asyncio.gather(*tasks)


@router.websocket("/vitals/{patient_id}/stream")
async def patient_stream(ws: WebSocket, patient_id: uuid.UUID) -> None:
    user = await authenticate(ws)
    if user is None:
        return
    if not user.can_view(patient_id):
        await ws.close(code=_FORBIDDEN, reason="Not your record")
        return
    wanted = str(patient_id)
    await _pump(ws, channels.VITALS, lambda e: e["patientId"] == wanted)


@router.websocket("/monitor/stream")
async def monitor_stream(ws: WebSocket) -> None:
    """Every patient's readings, for the care team's monitor."""
    user = await authenticate(ws)
    if user is None:
        return
    if not user.is_care_team:
        await ws.close(code=_FORBIDDEN, reason="Care team only")
        return
    await _pump(ws, channels.VITALS, lambda _: True)


@router.websocket("/escalations/stream")
async def escalation_stream(ws: WebSocket) -> None:
    user = await authenticate(ws)
    if user is None:
        return
    own = str(user.user_id)
    accept = (lambda _: True) if user.is_care_team else (lambda e: e["patientId"] == own)
    await _pump(ws, channels.ESCALATIONS, accept)
