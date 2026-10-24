"""Offline regression tests for App Store screenshot reuse decisions."""

from __future__ import annotations

import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent))
import update_app_store_listing as listing  # noqa: E402


class FakeClient:
    def __init__(self, existing_by_type: dict[str, list[dict[str, Any]]]) -> None:
        self.existing_by_type = existing_by_type
        self.calls: list[tuple[str, str, dict[str, Any] | None]] = []
        self.next_id = 0

    def get(self, path: str, params: dict[str, str] | None = None) -> dict[str, Any]:
        self.calls.append(("GET", path, params))
        if path.endswith("/appScreenshotSets"):
            return {"data": [
                {"id": f"set-{display_type}", "attributes": {"screenshotDisplayType": display_type}}
                for display_type in self.existing_by_type
            ]}
        if path.endswith("/appScreenshots") and "/appScreenshotSets/" in path:
            display_type = path.split("/appScreenshotSets/")[1].split("/")[0].removeprefix("set-")
            return {"data": self.existing_by_type[display_type]}
        if path.startswith("/appScreenshots/"):
            screenshot_id = path.rsplit("/", 1)[1]
            return {"data": {"id": screenshot_id, "attributes": {"assetDeliveryState": {"state": "COMPLETE"}}}}
        raise AssertionError(f"Unexpected GET {path}")

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        self.calls.append(("POST", path, payload))
        self.next_id += 1
        resource_type = "appScreenshotSets" if path == "/appScreenshotSets" else "appScreenshots"
        return {"data": {"id": f"new-{self.next_id}", "attributes": {"uploadOperations": []}, "type": resource_type}}

    def patch(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        self.calls.append(("PATCH", path, payload))
        return {}

    def delete(self, path: str) -> None:
        self.calls.append(("DELETE", path, None))


def screenshot(name: str, checksum: str | None, state: str = "COMPLETE") -> dict[str, Any]:
    attributes: dict[str, Any] = {"fileName": name, "assetDeliveryState": {"state": state}}
    if checksum is not None:
        attributes["sourceFileChecksum"] = checksum
    return {"id": f"old-{name}", "attributes": attributes}


class UploadScreenshotSetsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.local: dict[str, list[tuple[str, bytes]]] = {}
        for display_type, relative in listing.SCREENSHOT_SPECS.items():
            directory = self.root / relative
            directory.mkdir(parents=True)
            image = directory / "01-home.png"
            image.write_bytes(f"current image for {display_type}".encode())
            self.local[display_type] = [(image.name, image.read_bytes())]

    def tearDown(self) -> None:
        self.temp.cleanup()

    def existing(self, checksum_transform=lambda value: value, state: str = "COMPLETE") -> dict[str, list[dict[str, Any]]]:
        return {
            display_type: [
                screenshot(name, checksum_transform(hashlib.md5(content).hexdigest()), state)
                for name, content in entries
            ]
            for display_type, entries in self.local.items()
        }

    def run_upload(self, client: FakeClient, replace: bool = False) -> str:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            listing.upload_screenshot_sets(client, "localization-id", self.root, replace)
        return output.getvalue()

    def test_matching_order_content_and_complete_sets_are_reused(self) -> None:
        client = FakeClient(self.existing(lambda checksum: checksum.upper()))
        output = self.run_upload(client)
        self.assertIn("Kept existing APP_IPHONE_67 screenshot set", output)
        self.assertIn("Kept existing APP_IPAD_PRO_3GEN_129 screenshot set", output)
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _, _ in client.calls))

    def test_changed_bytes_with_same_filename_requires_explicit_replacement(self) -> None:
        existing = self.existing()
        existing["APP_IPHONE_67"][0]["attributes"]["sourceFileChecksum"] = hashlib.md5(b"old bytes").hexdigest()
        client = FakeClient(existing)
        with self.assertRaisesRegex(RuntimeError, "rerun with --replace-screenshots"):
            self.run_upload(client)
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _, _ in client.calls))

    def test_missing_remote_checksum_requires_explicit_replacement(self) -> None:
        client = FakeClient(self.existing(lambda checksum: None))
        with self.assertRaisesRegex(RuntimeError, "rerun with --replace-screenshots"):
            self.run_upload(client)
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _, _ in client.calls))

    def test_different_filename_is_not_reused(self) -> None:
        existing = self.existing()
        existing["APP_IPHONE_67"][0]["attributes"]["fileName"] = "old-home.png"
        client = FakeClient(existing)
        with self.assertRaisesRegex(RuntimeError, "rerun with --replace-screenshots"):
            self.run_upload(client)
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _, _ in client.calls))

    def test_incomplete_delivery_is_not_reused(self) -> None:
        client = FakeClient(self.existing(state="PROCESSING"))
        with self.assertRaisesRegex(RuntimeError, "rerun with --replace-screenshots"):
            self.run_upload(client)
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _, _ in client.calls))

    def test_order_mismatch_is_not_reused(self) -> None:
        for display_type, relative in listing.SCREENSHOT_SPECS.items():
            directory = self.root / relative
            second = directory / "02-next.png"
            second.write_bytes(f"second image for {display_type}".encode())
            self.local[display_type].append((second.name, second.read_bytes()))
        existing = self.existing()
        existing["APP_IPHONE_67"].reverse()
        client = FakeClient(existing)
        with self.assertRaisesRegex(RuntimeError, "rerun with --replace-screenshots"):
            self.run_upload(client)
        self.assertFalse(any(method in {"POST", "PATCH", "DELETE"} for method, _, _ in client.calls))

    def test_explicit_replacement_deletes_and_uploads_current_bytes(self) -> None:
        client = FakeClient(self.existing(lambda checksum: "stale"))
        self.run_upload(client, replace=True)
        deleted_sets = {path for method, path, _ in client.calls if method == "DELETE"}
        self.assertEqual(deleted_sets, {
            "/appScreenshotSets/set-APP_IPHONE_67",
            "/appScreenshotSets/set-APP_IPAD_PRO_3GEN_129",
        })
        uploaded_names = [
            payload["data"]["attributes"]["fileName"]
            for method, path, payload in client.calls
            if method == "POST" and path == "/appScreenshots"
        ]
        self.assertEqual(uploaded_names, ["01-home.png", "01-home.png"])
        checksum_patches = [
            payload["data"]["attributes"]["sourceFileChecksum"]
            for method, path, payload in client.calls
            if method == "PATCH" and path.startswith("/appScreenshots/")
        ]
        expected_checksums = [
            hashlib.md5(content).hexdigest()  # noqa: S324 - required by App Store Connect
            for display_type in listing.SCREENSHOT_SPECS
            for _, content in self.local[display_type]
        ]
        self.assertEqual(checksum_patches, expected_checksums)
        self.assertEqual(sum(method == "PATCH" for method, _, _ in client.calls), 4)


if __name__ == "__main__":
    unittest.main()
