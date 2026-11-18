"""AES-256-GCM for clinical values at rest.

Blob: version (1 byte) | nonce (12 bytes) | ciphertext+tag. The patient UUID
is the associated data, so a blob copied onto another patient's row won't
decrypt, and any tampering fails authentication.
"""

import base64
import json
import os
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

_VERSION = b"\x01"
_NONCE_BYTES = 12


class Cipher:
    def __init__(self, key_b64: str) -> None:
        try:
            key = base64.b64decode(key_b64, validate=True)
        except ValueError as e:
            raise ValueError("ENGINE_ENCRYPTION_KEY must be base64") from e
        if len(key) != 32:
            raise ValueError("ENGINE_ENCRYPTION_KEY must decode to 32 bytes (AES-256)")
        self._aead = AESGCM(key)

    def encrypt(self, data: dict[str, Any], associated: str) -> bytes:
        nonce = os.urandom(_NONCE_BYTES)
        plaintext = json.dumps(data, separators=(",", ":")).encode()
        return _VERSION + nonce + self._aead.encrypt(nonce, plaintext, associated.encode())

    def decrypt(self, blob: bytes, associated: str) -> dict[str, Any]:
        if blob[:1] != _VERSION:
            raise ValueError("Unknown ciphertext version")
        nonce = blob[1 : 1 + _NONCE_BYTES]
        plaintext = self._aead.decrypt(nonce, blob[1 + _NONCE_BYTES :], associated.encode())
        return json.loads(plaintext)
