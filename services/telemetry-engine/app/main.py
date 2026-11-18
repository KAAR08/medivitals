"""Telemetry engine: ingests and triages vitals, stores them encrypted,
streams them live, and signals calls between the care team and patients.

Run: uvicorn --factory app.main:create_app --no-access-log
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .auth import TokenVerifier
from .calls import Calls
from .config import Settings, get_settings
from .crypto import Cipher
from .db import Database
from .hub import create_hub
from .latch import StatusLatch
from .routes import calls, escalations, streams, telemetry
from .trends import TrendTracker

log = logging.getLogger("engine")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = settings
        app.state.cipher = Cipher(settings.encryption_key)  # fail fast on a bad key
        app.state.verifier = TokenVerifier(settings)
        app.state.db = Database(settings.database_dsn)
        app.state.hub = create_hub(settings.redis_url)
        app.state.trends = TrendTracker()
        app.state.latch = StatusLatch()
        app.state.calls = Calls(app.state.db.sessions, app.state.hub, app.state.cipher, settings)
        await app.state.db.create_schema()
        await app.state.hub.start()
        log.info("Telemetry engine ready")
        yield
        await app.state.calls.stop()
        await app.state.hub.stop()
        await app.state.db.dispose()

    app = FastAPI(
        title="MedVitals Telemetry Engine",
        version="1.0.0",
        lifespan=lifespan,
        docs_url="/docs" if settings.enable_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if settings.enable_docs else None,
    )

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        # API responses carry health data: never cache, never sniff.
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        return response

    @app.get("/health", tags=["ops"])
    async def health():
        """Liveness: the process is up."""
        return {"status": "ok"}

    @app.get("/ready", tags=["ops"])
    async def ready(request: Request):
        """Readiness: database and Redis reachable."""
        try:
            async with request.app.state.db.sessions() as session:
                await session.execute(text("SELECT 1"))
            db_ok = True
        except Exception:  # noqa: BLE001 - report, don't crash the probe
            db_ok = False
        hub_ok = await request.app.state.hub.ping()
        ok = db_ok and hub_ok
        return JSONResponse(
            {"status": "ready" if ok else "degraded", "database": db_ok, "redis": hub_ok},
            status_code=200 if ok else 503,
        )

    app.include_router(telemetry.router)
    app.include_router(escalations.router)
    app.include_router(streams.router)
    app.include_router(calls.router)
    return app
