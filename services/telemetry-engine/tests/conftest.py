import base64
import os
import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

JOHN = uuid.UUID("7c9e6679-7425-40de-944b-e07fc1f90ae7")
JANE = uuid.UUID("2f1a8b3c-9d4e-4f5a-8b6c-7d8e9f0a1b2c")
BOB = uuid.UUID("9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d")
NURSE = uuid.UUID("c4a2d3f5-6e7b-4c8d-9f0a-1b2c3d4e5f60")
DOCTOR = uuid.UUID("b3f1c2e4-5d6a-4b7c-8e9f-0a1b2c3d4e5f")
DEVICE_KEY = "test-device-key"

# One key pair per test session stands in for the Identity Service.
_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PUBLIC_PEM = (
    _private_key.public_key()
    .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    .decode()
)


def token(user: uuid.UUID, role: str, *, expires_in: int = 600, issuer: str = "medvitals-identity") -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "sub": str(user),
            "role": role,
            "iss": issuer,
            "aud": "medvitals-api",
            "iat": now,
            "exp": now + timedelta(seconds=expires_in),
        },
        _private_key,
        algorithm="RS256",
    )


def auth(user: uuid.UUID, role: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token(user, role)}"}


def reading(patient: uuid.UUID = JOHN, **overrides) -> dict:
    body = {
        "patientId": str(patient),
        "heartRate": 74,
        "spo2": 97.5,
        "systolicBP": 121,
        "diastolicBP": 79,
        "timestamp": datetime.now(UTC).isoformat(),
    }
    body.update(overrides)
    return body


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(
        database_url=f"sqlite+aiosqlite:///{tmp_path / 'test.db'}",
        encryption_key=base64.b64encode(os.urandom(32)).decode(),
        device_api_keys=[DEVICE_KEY],
        jwt_public_key=PUBLIC_PEM,
        _env_file=None,
    )


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def ingest(client: TestClient, **kwargs):
    return client.post("/telemetry", json=reading(**kwargs), headers={"X-Device-Key": DEVICE_KEY})
