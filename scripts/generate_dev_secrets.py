"""Create the secrets and settings docker-compose needs.

    python scripts/generate_dev_secrets.py            # first time
    python scripts/generate_dev_secrets.py --migrate  # move secrets out of an older .env

Each secret is its own file in secrets/ (mounted into containers as Docker
secrets); .env holds only non-secret settings. Both are git-ignored. Existing
files are never overwritten: a database initialised with one password won't
accept another.
"""

import argparse
import base64
import os
import secrets
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SECRETS = ROOT / "secrets"
ENV = ROOT / ".env"

# file name -> (key in an older .env, generator)
SECRET_FILES = {
    "postgres_password": ("POSTGRES_PASSWORD", lambda: secrets.token_urlsafe(24)),
    "mongo_password": ("MONGO_PASSWORD", lambda: secrets.token_urlsafe(24)),
    "encryption_key": ("ENGINE_ENCRYPTION_KEY", lambda: base64.b64encode(secrets.token_bytes(32)).decode()),
    "device_api_key": ("DEVICE_API_KEY", lambda: secrets.token_urlsafe(32)),
    "turn_secret": ("TURN_SECRET", lambda: secrets.token_urlsafe(32)),
    "seed_password": ("SEED_PASSWORD", lambda: secrets.token_urlsafe(12)),
}

SETTINGS = """\
# Non-secret settings for docker-compose (secrets live in secrets/).
# On a server (see docs/DEPLOYMENT.md):
#   GATEWAY_HOST=<DNS name>  GATEWAY_TLS_ISSUER=acme  GATEWAY_PORT=443  GATEWAY_HTTP_PORT=80
#   TURN_HOST=<DNS name>     TURN_EXTERNAL_IP=<public IP>
GATEWAY_HOST={GATEWAY_HOST}
GATEWAY_TLS_ISSUER={GATEWAY_TLS_ISSUER}
GATEWAY_PORT={GATEWAY_PORT}
GATEWAY_HTTP_PORT={GATEWAY_HTTP_PORT}
TURN_HOST={TURN_HOST}
TURN_EXTERNAL_IP={TURN_EXTERNAL_IP}
"""
DEFAULTS = {
    "GATEWAY_HOST": "localhost",
    "GATEWAY_TLS_ISSUER": "internal",
    "GATEWAY_PORT": "8443",
    "GATEWAY_HTTP_PORT": "8080",
    "TURN_HOST": "localhost",
    "TURN_EXTERNAL_IP": "127.0.0.1",
}


def rsa_private_key_pem() -> str:
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import rsa

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        return key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
        ).decode()
    except ImportError:
        return subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"],  # noqa: S607
            check=True,
            capture_output=True,
            text=True,
        ).stdout


def read_env() -> dict[str, str]:
    if not ENV.exists():
        return {}
    pairs = (line.split("=", 1) for line in ENV.read_text(encoding="utf-8").splitlines() if "=" in line)
    return {k.strip(): v.strip() for k, v in pairs if not k.strip().startswith("#")}


def write_secret(name: str, value: str) -> None:
    path = SECRETS / name
    path.write_text(value, encoding="utf-8")
    # Containers run as non-root users and need to read the file; the
    # directory itself is closed to other users on the host.
    path.chmod(0o644)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--migrate", action="store_true", help="move secrets from an older .env into secrets/"
    )
    args = parser.parse_args()

    old = read_env()
    if old and not args.migrate and any(key in old for key, _ in SECRET_FILES.values()):
        sys.exit(".env still holds secrets from an older version: run with --migrate")

    SECRETS.mkdir(exist_ok=True)
    if os.name == "posix":
        SECRETS.chmod(0o700)

    created = []
    for name, (old_key, generate) in SECRET_FILES.items():
        if not (SECRETS / name).exists():
            write_secret(name, old.get(old_key) or generate())
            created.append(name)
    if not (SECRETS / "jwt_private_key.pem").exists():
        write_secret("jwt_private_key.pem", rsa_private_key_pem())
        created.append("jwt_private_key.pem")

    settings = {key: old.get(key, default) for key, default in DEFAULTS.items()}
    if not ENV.exists() or args.migrate:
        ENV.write_text(SETTINGS.format(**settings), encoding="utf-8")

    print(f"secrets/: created {', '.join(created) or 'nothing (all present)'}")
    print("Demo accounts' password: see secrets/seed_password")


if __name__ == "__main__":
    main()
