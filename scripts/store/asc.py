#!/usr/bin/env python3
"""Minimal App Store Connect API client for release chores.

Reads the key from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (never prints the key).

    python3 scripts/store/asc.py check               # can this key see the app?
    python3 scripts/store/asc.py get /v1/apps/ID      # raw GET, prints JSON
    python3 scripts/store/asc.py install-profiles [NamePrefix]  # install Mac App Store profiles for Xcode
    python3 scripts/store/asc.py set-price APP_ID 5.99 BRA=34.9  # US base price + manual overrides
    python3 scripts/store/asc.py set-availability APP_ID CHN     # everywhere except the listed codes
    python3 scripts/store/asc.py set-age-rating APP_ID [userGeneratedContent]  # all None/No except the flags
    python3 scripts/store/asc.py set-urls APP_ID SUPPORT_URL PRIVACY_URL       # on every localization
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


def install_profiles(prefix: str = "Wakeful") -> int:
    """Installs the active Mac App Store profiles whose name starts with `prefix` where Xcode looks for them."""
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
        if not attributes["name"].startswith(prefix) or attributes["profileState"] != "ACTIVE":
            continue
        path = folder / f"{attributes['uuid']}.provisionprofile"
        path.write_bytes(base64.b64decode(attributes["profileContent"]))
        print(f"installed: {attributes['name']} → {path.name}")
        installed += 1
    return 0 if installed else 1


def price_point(app_id: str, territory: str, price: str) -> str | None:
    """Price point id for `price` (e.g. "5.99", "34.9") in `territory` (e.g. "USA", "BRA")."""
    path = f"/v1/apps/{app_id}/appPricePoints?filter%5Bterritory%5D={territory}&limit=200&fields%5BappPricePoints%5D=customerPrice"
    while path:
        status, body = request("GET", path.replace(API, ""))
        if status != 200:
            return None
        for point in body["data"]:
            if float(point["attributes"]["customerPrice"]) == float(price):
                return point["id"]
        path = body.get("links", {}).get("next")
    return None


def set_price(app_id: str, usd: str, *manual: str) -> int:
    """Sets the US price as base (other countries follow Apple's conversion) plus manual overrides
    given as TERRITORY=PRICE, e.g. BRA=34.9."""
    prices = [("USA", usd)] + [tuple(item.split("=", 1)) for item in manual]
    data, included = [], []
    for territory, price in prices:
        point = price_point(app_id, territory, price)
        if not point:
            print(f"no {territory} price point for {price}")
            return 1
        ref = "${" + territory + "}"
        data.append({"type": "appPrices", "id": ref})
        included.append({"type": "appPrices", "id": ref, "attributes": {"startDate": None},
                         "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point}}}})
    status, body = request("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": data}}},
        "included": included})
    print(f"price {app_id}: HTTP {status}", "" if status == 201 else body.get("errors"))
    return 0 if status == 201 else 1


def set_availability(app_id: str, *excluded: str) -> int:
    """Makes the app available everywhere (and in future territories) except `excluded` codes."""
    status, body = request("GET", "/v1/territories?limit=200")
    territories = [t["id"] for t in body["data"]]
    data, included = [], []
    for code in territories:
        ref = "${" + code + "}"
        data.append({"type": "territoryAvailabilities", "id": ref})
        included.append({"type": "territoryAvailabilities", "id": ref, "attributes": {"available": code not in excluded},
                         "relationships": {"territory": {"data": {"type": "territories", "id": code}}}})
    status, body = request("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": data}}},
        "included": included})
    available = len(territories) - len([c for c in territories if c in excluded])
    print(f"availability {app_id}: HTTP {status}, {available}/{len(territories)} territories",
          "" if status == 201 else body.get("errors"))
    return 0 if status == 201 else 1


AGE_RATING_LEVELS = [
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
    "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
    "sexualContentOrNudity", "horrorOrFearThemes", "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
    "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic",
]
AGE_RATING_FLAGS = [
    "advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat", "parentalControls",
    "ageAssurance", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess", "userGeneratedContent",
]


def editable_app_info(app_id: str) -> str | None:
    status, body = request("GET", f"/v1/apps/{app_id}/appInfos?fields%5BappInfos%5D=appStoreState")
    editable = [i for i in body.get("data", []) if i["attributes"].get("appStoreState") != "READY_FOR_SALE"]
    return (editable or body.get("data", [{}]))[0].get("id")


def set_age_rating(app_id: str, *yes: str) -> int:
    """Answers the age rating questionnaire with None/No, except the flags listed (e.g. userGeneratedContent)."""
    info = editable_app_info(app_id)
    status, body = request("GET", f"/v1/appInfos/{info}/ageRatingDeclaration")
    declaration = body["data"]["id"]
    attributes = {key: "NONE" for key in AGE_RATING_LEVELS}
    attributes |= {key: key in yes for key in AGE_RATING_FLAGS}
    status, body = request("PATCH", f"/v1/ageRatingDeclarations/{declaration}", {
        "data": {"type": "ageRatingDeclarations", "id": declaration, "attributes": attributes}})
    print(f"age rating {app_id}: HTTP {status}", "" if status == 200 else body.get("errors"))
    return 0 if status == 200 else 1


def set_urls(app_id: str, support: str, privacy: str) -> int:
    """Sets support/marketing URLs on every localization of the editable version and the privacy policy
    URL on every app info localization."""
    status, body = request("GET", f"/v1/apps/{app_id}/appStoreVersions?filter%5BappStoreState%5D="
                           "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED")
    failures = 0
    for version in body.get("data", []):
        status, locs = request("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")
        for loc in locs.get("data", []):
            status, _ = request("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {
                "data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                         "attributes": {"supportUrl": support, "marketingUrl": support}}})
            failures += status != 200
        print(f"support URL {app_id}: {len(locs.get('data', []))} version localizations")
    info = editable_app_info(app_id)
    status, locs = request("GET", f"/v1/appInfos/{info}/appInfoLocalizations?limit=50")
    for loc in locs.get("data", []):
        status, _ = request("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {
            "data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {"privacyPolicyUrl": privacy}}})
        failures += status != 200
    print(f"privacy URL {app_id}: {len(locs.get('data', []))} app info localizations, {failures} failures")
    return 0 if not failures else 1


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "set-age-rating":
        return set_age_rating(*sys.argv[2:])
    if command == "set-urls":
        return set_urls(*sys.argv[2:])
    if command == "check":
        return check()
    if command == "install-profiles":
        return install_profiles(*sys.argv[2:3])
    if command == "set-price":
        return set_price(*sys.argv[2:])
    if command == "set-availability":
        return set_availability(*sys.argv[2:])
    if command == "get":
        status, body = request("GET", sys.argv[2])
        print(status)
        print(json.dumps(body, indent=2, ensure_ascii=False))
        return 0 if status < 400 else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
