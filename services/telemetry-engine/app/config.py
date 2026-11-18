"""Runtime configuration from ENGINE_* environment variables, and from files
in /run/secrets (Docker secrets: a file named e.g. engine_encryption_key)."""

import json
from functools import lru_cache
from pathlib import Path
from typing import Annotated

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict
from sqlalchemy.engine import make_url

_SECRETS = Path("/run/secrets")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="ENGINE_",
        env_file=".env",
        extra="ignore",
        secrets_dir=_SECRETS if _SECRETS.is_dir() else None,
    )

    # SQLite for local development and tests; production uses
    # postgresql+asyncpg://user@host/db with the password kept separately.
    database_url: str = "sqlite+aiosqlite:///./telemetry.db"
    database_password: str | None = None

    # Real-time fan-out. Unset → single-process in-memory hub.
    redis_url: str | None = None

    # AES-256-GCM key for data at rest: 32 random bytes, base64-encoded.
    # Generate with: python -c "import os,base64;print(base64.b64encode(os.urandom(32)).decode())"
    encryption_key: str

    # Keys for ingestion devices (the biometric simulator): a JSON list or
    # comma-separated.
    device_api_keys: Annotated[list[str], NoDecode] = Field(default_factory=list)

    # Access tokens are issued by the Identity Service (RS256). Verify with its
    # JWKS endpoint, or with a PEM public key (tests, air-gapped deployments).
    jwks_url: str | None = None
    jwt_public_key: str | None = None
    jwt_issuer: str = "medvitals-identity"
    jwt_audience: str = "medvitals-api"

    # Voice/video calls (WebRTC). TURN relays media when the two devices can't
    # reach each other directly (e.g. both behind mobile-carrier NAT). The
    # engine hands out short-lived TURN credentials signed with turn_secret
    # (coturn's "use-auth-secret" scheme), so no long-lived password ships in
    # the app. Without TURN, calls still work when devices can reach each
    # other (same network or same machine).
    turn_urls: list[str] = Field(default_factory=list)
    turn_secret: str | None = None
    turn_ttl_seconds: int = 3600
    stun_urls: list[str] = Field(default_factory=list)
    # How long a call rings before it counts as missed.
    call_ring_seconds: int = 30

    # Interactive API docs at /docs. Disable in production.
    enable_docs: bool = True

    @field_validator("device_api_keys", mode="before")
    @classmethod
    def _keys(cls, value: object) -> object:
        if isinstance(value, str):
            value = value.strip()
            if value.startswith("["):
                return json.loads(value)
            return [k.strip() for k in value.split(",") if k.strip()]
        return value

    @property
    def database_dsn(self) -> str:
        """The database URL with the password (kept out of the URL itself)."""
        if not self.database_password:
            return self.database_url
        return (
            make_url(self.database_url)
            .set(password=self.database_password)
            .render_as_string(hide_password=False)
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
