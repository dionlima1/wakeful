#!/usr/bin/env python3
"""Minimal App Store Connect API client for release chores.

Reads the key from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (never prints the key).

    python3 scripts/store/asc.py check               # can this key see the app?
    python3 scripts/store/asc.py get /v1/apps/ID      # raw GET, prints JSON
    python3 scripts/store/asc.py install-profiles     # install Mac App Store profiles for Xcode
"""
import base64
import json
import os
import pathlib
import ssl
import sys
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

API = "https://api.appstoreconnect.apple.com"
# python.org builds ship without CA roots; fall back to the macOS bundle.
SSL_CONTEXT = ssl.create_default_context(cafile="/etc/ssl/cert.pem" if os.path.exists("/etc/ssl/cert.pem") else None)
BUNDLE_ID = "com.dionlima.wakeful"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token() -> str:
    key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
    key_path = pathlib.Path(os.path.expanduser(os.environ["ASC_KEY_PATH"]))
    private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    der = private_key.sign(f"{header}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return f"{header}.{payload}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


def request(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, context=SSL_CONTEXT) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read()
        return error.code, json.loads(raw) if raw else {}


def check() -> int:
    status, body = request("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=name,bundleId,sku")
    if status != 200:
        print(f"HTTP {status}: {body.get('errors', [{}])[0].get('detail', body)}")
        return 1
    apps = body.get("data", [])
    for app in apps:
        print(f"ok: {app['attributes']['name']} ({app['attributes']['bundleId']}) id={app['id']}")
    if not apps:
        print("ok: key works, but the app was not found")
    return 0


def install_profiles() -> int:
    """Installs the active Mac App Store profiles named "Wakeful…" where Xcode looks for them."""
    status, body = request("GET", "/v1/profiles?filter%5BprofileType%5D=MAC_APP_STORE"
                           "&fields%5Bprofiles%5D=name,uuid,profileState,profileContent&limit=200")
    if status != 200:
        print(f"HTTP {status}: {body}")
        return 1
    folder = pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    folder.mkdir(parents=True, exist_ok=True)
    installed = 0
    for profile in body.get("data", []):
        attributes = profile["attributes"]
        if not attributes["name"].startswith("Wakeful") or attributes["profileState"] != "ACTIVE":
            continue
        path = folder / f"{attributes['uuid']}.provisionprofile"
        path.write_bytes(base64.b64decode(attributes["profileContent"]))
        print(f"installed: {attributes['name']} → {path.name}")
        installed += 1
    return 0 if installed else 1


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "check":
        return check()
    if command == "install-profiles":
        return install_profiles()
    if command == "get":
        status, body = request("GET", sys.argv[2])
        print(status)
        print(json.dumps(body, indent=2, ensure_ascii=False))
        return 0 if status < 400 else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
