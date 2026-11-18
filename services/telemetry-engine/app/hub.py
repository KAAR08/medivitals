"""Event fan-out to WebSocket clients.

Events go through Redis pub/sub, so a reading ingested by one engine instance
reaches clients connected to any instance. Without Redis (development,
tests) they're delivered in-process.
"""

import asyncio
import contextlib
import json
import logging
from collections import defaultdict
from collections.abc import AsyncIterator
from typing import Any

log = logging.getLogger("engine.hub")

VITALS = "vitals"
ESCALATIONS = "escalations"
CALLS = "calls"  # call signalling, addressed to a user or to every nurse
CHANNELS = (VITALS, ESCALATIONS, CALLS)

_QUEUE_SIZE = 256


class _LocalFanout:
    def __init__(self) -> None:
        self._subscribers: dict[str, set[asyncio.Queue[dict[str, Any]]]] = defaultdict(set)

    def deliver(self, channel: str, message: dict[str, Any]) -> None:
        for queue in list(self._subscribers[channel]):
            if queue.full():
                # A slow client must not stall the pipeline: drop its oldest event.
                with contextlib.suppress(asyncio.QueueEmpty):
                    queue.get_nowait()
            queue.put_nowait(message)

    @contextlib.asynccontextmanager
    async def subscribe(self, channel: str) -> AsyncIterator[asyncio.Queue[dict[str, Any]]]:
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=_QUEUE_SIZE)
        self._subscribers[channel].add(queue)
        try:
            yield queue
        finally:
            self._subscribers[channel].discard(queue)


class Hub:
    """In-process hub. Subclassed by RedisHub for multi-instance deployments."""

    def __init__(self) -> None:
        self._local = _LocalFanout()

    async def start(self) -> None:
        pass

    async def stop(self) -> None:
        pass

    async def ping(self) -> bool:
        return True

    async def publish(self, channel: str, message: dict[str, Any]) -> None:
        self._local.deliver(channel, message)

    def subscribe(self, channel: str):
        return self._local.subscribe(channel)


class RedisHub(Hub):
    def __init__(self, url: str) -> None:
        super().__init__()
        from redis.asyncio import Redis

        self._redis = Redis.from_url(url)
        self._listener: asyncio.Task[None] | None = None

    async def start(self) -> None:
        self._listener = asyncio.create_task(self._listen(), name="redis-listener")

    async def stop(self) -> None:
        if self._listener:
            self._listener.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._listener
        await self._redis.aclose()

    async def ping(self) -> bool:
        try:
            return bool(await self._redis.ping())
        except Exception:  # noqa: BLE001 - readiness probe reports any failure
            return False

    async def publish(self, channel: str, message: dict[str, Any]) -> None:
        await self._redis.publish(channel, json.dumps(message))

    async def _listen(self) -> None:
        while True:
            try:
                pubsub = self._redis.pubsub()
                await pubsub.subscribe(*CHANNELS)
                async for item in pubsub.listen():
                    if item["type"] == "message":
                        channel = item["channel"].decode()
                        self._local.deliver(channel, json.loads(item["data"]))
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001 - keep listening through Redis restarts
                log.exception("Redis subscription failed; retrying in 2 s")
                await asyncio.sleep(2)


def create_hub(redis_url: str | None) -> Hub:
    return RedisHub(redis_url) if redis_url else Hub()
