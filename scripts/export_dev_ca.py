"""Export the development gateway's root certificate for the Flutter app.

The gateway (Caddy, `tls internal`) creates its own certificate authority the
first time it starts. This copies that root certificate (public, not the key)
out of the running container into secrets/dev_ca.json, in the format
`flutter run --dart-define-from-file` expects:

    docker compose up -d
    python scripts/export_dev_ca.py
    flutter run --dart-define-from-file=secrets/dev_ca.json \
                --dart-define=USE_MOCK_BACKEND=false

Re-run it if the gateway's data volume is deleted (a new CA is created).
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CA_PATH = "/data/caddy/pki/authorities/local/root.crt"


def main() -> int:
    result = subprocess.run(  # noqa: S603 - fixed argument list, no shell
        ["docker", "compose", "exec", "-T", "gateway", "cat", CA_PATH],  # noqa: S607
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    pem = result.stdout.strip()
    if result.returncode != 0 or "BEGIN CERTIFICATE" not in pem:
        print("Could not read the gateway CA. Is the stack running? (docker compose up -d)", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
        return 1

    out = ROOT / "secrets" / "dev_ca.json"
    out.parent.mkdir(exist_ok=True)
    # The base64 body only: Flutter can't pass build values containing
    # newlines or spaces on Windows hosts, so the app rebuilds the PEM.
    body = "".join(line for line in pem.splitlines() if line and not line.startswith("-----"))
    out.write_text(json.dumps({"DEV_CA_CERT": body}, indent=2) + "\n", encoding="utf-8")
    (ROOT / "secrets" / "dev_ca.crt").write_text(pem + "\n", encoding="utf-8")
    print(f"Wrote {out.relative_to(ROOT)} (and dev_ca.crt for curl --cacert)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
