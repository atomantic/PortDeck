#!/usr/bin/env python3
"""Populate the PortOS App Store listing and upload submission screenshots."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


API_ROOT = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_BUNDLE_ID = "net.shadowpuppet.PortDeck"
DEFAULT_CONTACT_SOURCE_BUNDLE_ID = "net.shadowpuppet.EscapeMint"
DEFAULT_LOCALE = "en-US"
DEFAULT_VERSION = "1.0"
SCREENSHOT_SPECS = {
    "APP_IPHONE_67": Path("screenshots/en/iphone_6.9"),
    "APP_IPAD_PRO_3GEN_129": Path("screenshots/en/ipad_13"),
}
AGE_RATING_ATTRIBUTES = {
    "advertising": False,
    "ageAssurance": False,
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "contests": "NONE",
    "gambling": False,
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE",
    "healthOrWellnessTopics": False,
    "horrorOrFearThemes": "NONE",
    "lootBox": False,
    "matureOrSuggestiveThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE",
    "messagingAndChat": False,
    "parentalControls": False,
    "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "NONE",
    "socialMedia": False,
    "socialMediaAgeRestricted": False,
    "unrestrictedWebAccess": False,
    "userGeneratedContent": False,
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
}


def load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        raise RuntimeError(f"Environment file not found: {path}")
    values: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def sign_token(key_id: str, issuer_id: str, key_path: Path) -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(
        json.dumps(
            {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = header + b"." + claims
    signature = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout

    if not signature or signature[0] != 0x30:
        raise RuntimeError("openssl returned an unexpected ECDSA signature")
    index = 2 if signature[1] < 0x80 else 2 + (signature[1] & 0x7F)
    r_length = signature[index + 1]
    r = signature[index + 2 : index + 2 + r_length]
    index += 2 + r_length
    s_length = signature[index + 1]
    s = signature[index + 2 : index + 2 + s_length]
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    return (signing_input + b"." + b64url(r + s)).decode()


class AppStoreConnect:
    def __init__(self, token: str) -> None:
        self.token = token

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            f"{API_ROOT}{path}",
            data=body,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise RuntimeError(f"{method} {path} failed with HTTP {error.code}: {detail}") from error
        return json.loads(raw) if raw else {}

    def get(self, path: str, params: dict[str, str] | None = None) -> dict[str, Any]:
        query = "" if not params else "?" + urllib.parse.urlencode(params)
        return self.request("GET", path + query)

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", path, payload)

    def patch(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("PATCH", path, payload)

    def delete(self, path: str) -> None:
        self.request("DELETE", path)


def first(response: dict[str, Any], label: str) -> dict[str, Any]:
    data = response.get("data")
    if not data:
        raise RuntimeError(f"No {label} found")
    return data[0] if isinstance(data, list) else data


def parse_metadata(path: Path) -> dict[str, str]:
    text = path.read_text()
    product_match = re.search(r"## Product page\n(?P<body>.*?)\n## Description", text, re.DOTALL)
    description_match = re.search(r"## Description\n(?P<body>.*?)\n## App Review notes", text, re.DOTALL)
    review_match = re.search(r"## App Review notes\n(?P<body>.*)$", text, re.DOTALL)
    if not product_match or not description_match or not review_match:
        raise RuntimeError(f"Could not parse required sections in {path}")

    metadata: dict[str, str] = {}
    for label, value in re.findall(r"^- ([^:]+):\s+`([^`]*)`$", product_match.group("body"), re.MULTILINE):
        metadata[label.lower().replace(" ", "_")] = value
    required = {
        "name",
        "subtitle",
        "promotional_text",
        "keywords",
        "marketing_url",
        "support_url",
        "privacy_policy_url",
        "copyright",
    }
    missing = required - metadata.keys()
    if missing:
        raise RuntimeError(f"Missing metadata fields: {', '.join(sorted(missing))}")
    metadata["description"] = description_match.group("body").strip()
    metadata["review_notes"] = review_match.group("body").strip().replace("**", "")
    return metadata


def find_app(client: AppStoreConnect, bundle_id: str) -> dict[str, Any]:
    return first(client.get("/apps", {"filter[bundleId]": bundle_id, "limit": "1"}), f"app {bundle_id}")


def find_app_info(client: AppStoreConnect, app_id: str) -> dict[str, Any]:
    return first(client.get(f"/apps/{app_id}/appInfos", {"limit": "1"}), "app info")


def find_app_info_localization(
    client: AppStoreConnect, app_info_id: str, locale: str
) -> dict[str, Any]:
    return first(
        client.get(
            f"/appInfos/{app_info_id}/appInfoLocalizations",
            {"filter[locale]": locale, "limit": "1"},
        ),
        f"app info localization {locale}",
    )


def find_version(client: AppStoreConnect, app_id: str, version: str) -> dict[str, Any]:
    return first(
        client.get(
            f"/apps/{app_id}/appStoreVersions",
            {"filter[platform]": "IOS", "filter[versionString]": version, "limit": "1"},
        ),
        f"iOS App Store version {version}",
    )


def find_version_localization(
    client: AppStoreConnect, version_id: str, locale: str
) -> dict[str, Any]:
    return first(
        client.get(
            f"/appStoreVersions/{version_id}/appStoreVersionLocalizations",
            {"filter[locale]": locale, "limit": "1"},
        ),
        f"version localization {locale}",
    )


def update_listing(
    client: AppStoreConnect,
    app: dict[str, Any],
    app_info: dict[str, Any],
    info_localization: dict[str, Any],
    version: dict[str, Any],
    version_localization: dict[str, Any],
    metadata: dict[str, str],
) -> None:
    app_id = app["id"]
    client.patch(
        f"/apps/{app_id}",
        {
            "data": {
                "type": "apps",
                "id": app_id,
                "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"},
            }
        },
    )

    app_info_id = app_info["id"]
    client.patch(
        f"/appInfos/{app_info_id}",
        {
            "data": {
                "type": "appInfos",
                "id": app_info_id,
                "relationships": {
                    "primaryCategory": {
                        "data": {"type": "appCategories", "id": "PRODUCTIVITY"}
                    },
                    "secondaryCategory": {
                        "data": {"type": "appCategories", "id": "UTILITIES"}
                    },
                },
            }
        },
    )

    info_localization_id = info_localization["id"]
    client.patch(
        f"/appInfoLocalizations/{info_localization_id}",
        {
            "data": {
                "type": "appInfoLocalizations",
                "id": info_localization_id,
                "attributes": {
                    "subtitle": metadata["subtitle"],
                    "privacyPolicyUrl": metadata["privacy_policy_url"],
                },
            }
        },
    )

    version_localization_id = version_localization["id"]
    client.patch(
        f"/appStoreVersionLocalizations/{version_localization_id}",
        {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": version_localization_id,
                "attributes": {
                    "description": metadata["description"],
                    "keywords": metadata["keywords"],
                    "marketingUrl": metadata["marketing_url"],
                    "promotionalText": metadata["promotional_text"],
                    "supportUrl": metadata["support_url"],
                },
            }
        },
    )

    version_id = version["id"]
    client.patch(
        f"/appStoreVersions/{version_id}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": {
                    "copyright": metadata["copyright"],
                    "releaseType": "MANUAL",
                },
            }
        },
    )
    print("Updated product-page copy, categories, rights, privacy URL, and release settings")


def update_age_rating(client: AppStoreConnect, app_info_id: str) -> None:
    declaration = first(
        client.get(f"/appInfos/{app_info_id}/ageRatingDeclaration"),
        "age rating declaration",
    )
    declaration_id = declaration["id"]
    client.patch(
        f"/ageRatingDeclarations/{declaration_id}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": declaration_id,
                "attributes": AGE_RATING_ATTRIBUTES,
            }
        },
    )
    print("Completed the age-rating declaration with no restricted content")


def review_contact_from_app(client: AppStoreConnect, bundle_id: str) -> dict[str, str]:
    source_app = find_app(client, bundle_id)
    versions = client.get(
        f"/apps/{source_app['id']}/appStoreVersions",
        {"filter[platform]": "IOS", "limit": "50"},
    ).get("data", [])
    for source_version in versions:
        try:
            detail = first(
                client.get(f"/appStoreVersions/{source_version['id']}/appStoreReviewDetail"),
                "source review detail",
            )
        except RuntimeError:
            continue
        attributes = detail.get("attributes", {})
        fields = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
        if all(attributes.get(field) for field in fields):
            return {field: attributes[field] for field in fields}
    raise RuntimeError(f"No complete App Review contact found for {bundle_id}")


def update_review_detail(
    client: AppStoreConnect,
    version_id: str,
    review_notes: str,
    contact_source_bundle_id: str,
) -> None:
    contact = review_contact_from_app(client, contact_source_bundle_id)
    attributes: dict[str, Any] = {
        **contact,
        "demoAccountRequired": False,
        "notes": review_notes,
    }
    try:
        detail = first(
            client.get(f"/appStoreVersions/{version_id}/appStoreReviewDetail"),
            "review detail",
        )
    except RuntimeError:
        detail = None

    if detail:
        detail_id = detail["id"]
        client.patch(
            f"/appStoreReviewDetails/{detail_id}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": detail_id,
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
        )
    print("Updated App Review contact and offline-demo instructions")


def find_build(client: AppStoreConnect, app_id: str, build_number: str) -> dict[str, Any]:
    response = client.get(
        "/builds",
        {
            "filter[app]": app_id,
            "filter[version]": build_number,
            "filter[processingState]": "VALID",
            "sort": "-uploadedDate",
            "limit": "1",
        },
    )
    return first(response, f"valid build {build_number}")


def attach_build(client: AppStoreConnect, version_id: str, app_id: str, build_number: str) -> None:
    build = find_build(client, app_id, build_number)
    client.patch(
        f"/appStoreVersions/{version_id}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build["id"]}}
                },
            }
        },
    )
    print(f"Selected build {build_number} for App Store version {DEFAULT_VERSION}")


def upload_operation(operation: dict[str, Any], screenshot_path: Path) -> None:
    offset = int(operation["offset"])
    length = int(operation["length"])
    with screenshot_path.open("rb") as screenshot:
        screenshot.seek(offset)
        chunk = screenshot.read(length)
    if len(chunk) != length:
        raise RuntimeError(f"Could not read upload byte range for {screenshot_path}")
    headers = {header["name"]: header["value"] for header in operation.get("requestHeaders", [])}
    request = urllib.request.Request(
        operation["url"],
        data=chunk,
        method=operation.get("method", "PUT"),
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(
            f"Screenshot upload failed for {screenshot_path.name} with HTTP {error.code}: {detail}"
        ) from error


def create_screenshot_set(
    client: AppStoreConnect, localization_id: str, display_type: str
) -> dict[str, Any]:
    return first(
        client.post(
            "/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {
                                "type": "appStoreVersionLocalizations",
                                "id": localization_id,
                            }
                        }
                    },
                }
            },
        ),
        f"created screenshot set {display_type}",
    )


def upload_screenshot(
    client: AppStoreConnect, screenshot_set_id: str, path: Path
) -> dict[str, Any]:
    reservation = first(
        client.post(
            "/appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileSize": path.stat().st_size, "fileName": path.name},
                    "relationships": {
                        "appScreenshotSet": {
                            "data": {"type": "appScreenshotSets", "id": screenshot_set_id}
                        }
                    },
                }
            },
        ),
        f"screenshot reservation for {path.name}",
    )
    for operation in reservation.get("attributes", {}).get("uploadOperations", []):
        upload_operation(operation, path)

    checksum = hashlib.md5(path.read_bytes()).hexdigest()  # noqa: S324 - required by App Store Connect
    screenshot_id = reservation["id"]
    client.patch(
        f"/appScreenshots/{screenshot_id}",
        {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
            }
        },
    )

    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        screenshot = first(client.get(f"/appScreenshots/{screenshot_id}"), path.name)
        delivery = screenshot.get("attributes", {}).get("assetDeliveryState", {})
        state = delivery.get("state")
        if state == "COMPLETE":
            return screenshot
        if state == "FAILED":
            raise RuntimeError(f"Apple rejected {path.name}: {delivery.get('errors', delivery)}")
        time.sleep(2)
    raise RuntimeError(f"Timed out waiting for Apple to process {path.name}")


def upload_screenshot_sets(
    client: AppStoreConnect,
    localization_id: str,
    root: Path,
    replace: bool,
) -> None:
    existing_sets = client.get(
        f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets",
        {"limit": "50"},
    ).get("data", [])
    by_display_type = {
        item.get("attributes", {}).get("screenshotDisplayType"): item for item in existing_sets
    }

    for display_type, relative_directory in SCREENSHOT_SPECS.items():
        directory = root / relative_directory
        paths = sorted(directory.glob("*.png"))
        if not paths:
            raise RuntimeError(f"No screenshots found in {directory}")

        screenshot_set = by_display_type.get(display_type)
        if screenshot_set and replace:
            client.delete(f"/appScreenshotSets/{screenshot_set['id']}")
            screenshot_set = None
        if screenshot_set:
            existing = client.get(
                f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots",
                {"limit": "10"},
            ).get("data", [])
            expected_names = [path.name for path in paths]
            actual_names = [item.get("attributes", {}).get("fileName") for item in existing]
            complete = all(
                item.get("attributes", {}).get("assetDeliveryState", {}).get("state") == "COMPLETE"
                for item in existing
            )
            if actual_names == expected_names and complete:
                print(f"Kept existing {display_type} screenshot set ({len(existing)} images)")
                continue
            raise RuntimeError(
                f"{display_type} already has a different screenshot set; rerun with --replace-screenshots"
            )

        screenshot_set = create_screenshot_set(client, localization_id, display_type)
        uploaded = []
        for path in paths:
            uploaded.append(upload_screenshot(client, screenshot_set["id"], path))
            print(f"Uploaded {display_type} {path.name}")
        client.patch(
            f"/appScreenshotSets/{screenshot_set['id']}/relationships/appScreenshots",
            {
                "data": [
                    {"type": "appScreenshots", "id": screenshot["id"]}
                    for screenshot in uploaded
                ]
            },
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--version", default=DEFAULT_VERSION)
    parser.add_argument("--locale", default=DEFAULT_LOCALE)
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument("--metadata-file", type=Path, default=Path("APP_STORE_METADATA.md"))
    parser.add_argument("--screenshot-root", type=Path, default=Path("."))
    parser.add_argument("--skip-screenshots", action="store_true")
    parser.add_argument("--replace-screenshots", action="store_true")
    parser.add_argument("--skip-age-rating", action="store_true")
    parser.add_argument("--skip-review-detail", action="store_true")
    parser.add_argument("--build-number")
    parser.add_argument(
        "--review-contact-source-bundle-id",
        default=DEFAULT_CONTACT_SOURCE_BUNDLE_ID,
        help="Copies only App Review contact fields; no credentials are copied",
    )
    args = parser.parse_args()

    metadata = parse_metadata(args.metadata_file)
    env = load_env(args.env_file)
    key_path = Path(os.path.expandvars(env["APPSTORE_API_PRIVATE_KEY_PATH"])).expanduser()
    token = sign_token(env["APPSTORE_API_KEY_ID"], env["APPSTORE_ISSUER_ID"], key_path)
    client = AppStoreConnect(token)

    app = find_app(client, args.bundle_id)
    app_info = find_app_info(client, app["id"])
    info_localization = find_app_info_localization(client, app_info["id"], args.locale)
    version = find_version(client, app["id"], args.version)
    version_localization = find_version_localization(client, version["id"], args.locale)

    update_listing(
        client,
        app,
        app_info,
        info_localization,
        version,
        version_localization,
        metadata,
    )
    if not args.skip_age_rating:
        update_age_rating(client, app_info["id"])
    if not args.skip_review_detail:
        update_review_detail(
            client,
            version["id"],
            metadata["review_notes"],
            args.review_contact_source_bundle_id,
        )
    if not args.skip_screenshots:
        upload_screenshot_sets(
            client,
            version_localization["id"],
            args.screenshot_root,
            args.replace_screenshots,
        )
    if args.build_number:
        attach_build(client, version["id"], app["id"], args.build_number)
    print(f"App Store listing updated for Apple ID {app['id']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
