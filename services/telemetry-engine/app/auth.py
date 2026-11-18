"""Authentication and role-based access.

- Users present an RS256 access token issued by the Identity Service.
  Claims: sub (user UUID), role (patient | doctor | nurse), iss, aud, exp.
  The engine only verifies tokens; it never sees passwords.
- Ingestion devices (the biometric simulator) present an API key.

Access rule: a patient may only see their own data; the care team (doctors,
nurses) may see every patient on the ward.
"""

import asyncio
import hmac
import uuid
from dataclasses import dataclass
from enum import StrEnum
from typing import Annotated

import jwt
from fastapi import Depends, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings


class Role(StrEnum):
    PATIENT = "patient"
    DOCTOR = "doctor"
    NURSE = "nurse"


@dataclass(frozen=True)
class Principal:
    user_id: uuid.UUID
    role: Role

    @property
    def is_care_team(self) -> bool:
        return self.role in (Role.DOCTOR, Role.NURSE)

    def can_view(self, patient_id: uuid.UUID) -> bool:
        return self.is_care_team or self.user_id == patient_id


class AuthError(Exception):
    pass


class TokenVerifier:
    def __init__(self, settings: Settings) -> None:
        self._issuer = settings.jwt_issuer
        self._audience = settings.jwt_audience
        self._static_key = settings.jwt_public_key
        self._jwks = jwt.PyJWKClient(settings.jwks_url, cache_keys=True) if settings.jwks_url else None
        if not (self._static_key or self._jwks):
            raise ValueError("Set ENGINE_JWKS_URL or ENGINE_JWT_PUBLIC_KEY to verify access tokens")

    async def verify(self, token: str) -> Principal:
        try:
            if self._jwks:
                # PyJWKClient is synchronous (and caches keys); keep it off the event loop.
                signing_key = await asyncio.to_thread(self._jwks.get_signing_key_from_jwt, token)
                key = signing_key.key
            else:
                key = self._static_key
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256"],  # pinned: never accept "none" or HS256 confusion
                issuer=self._issuer,
                audience=self._audience,
                options={"require": ["exp", "sub", "iss", "aud"]},
            )
            return Principal(uuid.UUID(claims["sub"]), Role(claims["role"]))
        except (jwt.PyJWTError, KeyError, ValueError) as e:
            raise AuthError(str(e)) from e


_bearer = HTTPBearer(auto_error=False)


async def current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing access token")
    try:
        return await request.app.state.verifier.verify(credentials.credentials)
    except AuthError:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Access token is invalid or expired",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None


async def care_team(user: Annotated[Principal, Depends(current_user)]) -> Principal:
    if not user.is_care_team:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Care team only")
    return user


async def device(request: Request, x_device_key: Annotated[str | None, Header()] = None) -> None:
    keys: list[str] = request.app.state.settings.device_api_keys
    # Constant-time comparison so response timing doesn't leak the key.
    if not x_device_key or not any(hmac.compare_digest(x_device_key, k) for k in keys):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Unknown device")


CurrentUser = Annotated[Principal, Depends(current_user)]
CareTeam = Annotated[Principal, Depends(care_team)]
Device = Annotated[None, Depends(device)]
