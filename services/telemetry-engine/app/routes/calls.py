"""Voice/video call signalling (see app/calls.py for the rules)."""

import asyncio
import contextlib
import json
from collections import Counter

import anyio
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect

from .. import hub as channels
from ..auth import CurrentUser
from ..calls import CallError, ice_servers
from .streams import authenticate

router = APIRouter(tags=["calls"])

# Open signalling connections per user on this instance: a user's calls end
# only when their last connection closes.
_connections: Counter[str] = Counter()


@router.get("/calls/ice-servers")
async def get_ice_servers(user: CurrentUser, request: Request):
    """STUN/TURN servers for WebRTC, with TURN credentials valid for `ttl` seconds."""
    return ice_servers(request.app.state.settings, user)


@router.websocket("/calls/signal")
async def signal(ws: WebSocket) -> None:
    """One connection per signed-in app: rings, answers, hang-ups and WebRTC session data."""
    user = await authenticate(ws)
    if user is None:
        return
    calls = ws.app.state.calls
    key = str(user.user_id)
    _connections[key] += 1
    try:
        # Subscribe before accepting, so no call can ring in between.
        async with ws.app.state.hub.subscribe(channels.CALLS) as queue:
            await ws.accept()
            await calls.redeliver(user)  # reconnected while a call rings for them

            async def deliver() -> None:
                while True:
                    envelope = await queue.get()
                    if calls.addressed_to(user, envelope):
                        await ws.send_json(envelope["msg"])

            async def receive() -> None:
                while True:
                    message = await ws.receive()
                    if message["type"] == "websocket.disconnect":
                        return
                    try:
                        raw = json.loads(message.get("text") or "")
                        if not isinstance(raw, dict):
                            raise CallError("Expected a JSON object")
                        await calls.handle(user, raw)
                    except json.JSONDecodeError:
                        await ws.send_json({"type": "error", "message": "Expected JSON"})
                    except CallError as e:
                        error = {"type": "error", "message": str(e)}
                        if e.call_id:
                            error["callId"] = str(e.call_id)
                        await ws.send_json(error)

            tasks = [asyncio.create_task(deliver()), asyncio.create_task(receive())]
            _, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
            with contextlib.suppress(asyncio.CancelledError, WebSocketDisconnect, RuntimeError):
                await asyncio.gather(*tasks)
    finally:
        _connections[key] -= 1
        if _connections[key] <= 0:
            del _connections[key]
            # The connection may be closing because its task was cancelled;
            # the other party must still be told the call ended.
            with anyio.CancelScope(shield=True):
                await calls.disconnected(user)
