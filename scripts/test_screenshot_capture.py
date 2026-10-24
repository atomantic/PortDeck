"""Exercise the capture script with filesystem artifacts and fake Xcode tools."""

import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
CURRENT = re.findall(r'try saveScreenshot\("([^"]+)"\)',
                     (ROOT / "PortDeckUITests/ScreenshotTests.swift").read_text())
HISTORICAL = ["01_fleet", "02_federation", "03_capture", "04_actions",
              "05_action_results", "06_action_form", "07_privacy"]
DEVICES = ("iphone_6.9", "ipad_13")
MOCK_TOOL = '''#!/usr/bin/env python3
import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
if tool == "xcrun" and sys.argv[1:4] == ["simctl", "list", "devices"]:
    print(json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-3": [
        {"name": "iPhone 17 Pro Max", "udid": "phone", "isAvailable": True},
        {"name": "iPad Pro 13-inch (M5)", "udid": "pad", "isAvailable": True}]}}))
elif tool == "xcodebuild" and sys.argv[1] == "test-without-building":
    config = json.loads(pathlib.Path(".screenshot_config.json").read_text())
    output = pathlib.Path(config["output_dir"]) / "en" / config["device"]
    assert ".capture." in str(output), "Capture must use an isolated directory"
    output.mkdir(parents=True)
    names = json.loads(os.environ["MOCK_SCREENS"])
    if config["target_screen"]:
        names = [name for name in names if name == config["target_screen"]]
    if os.environ.get("MOCK_CAPTURE") == "empty":
        names = []
    for name in names:
        (output / (name + ".png")).write_bytes(b"fresh image")
        if os.environ.get("MOCK_CAPTURE") == "fail":
            sys.exit(1)
'''


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ScreenshotCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="screenshot-capture-test-")
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name)
        (self.project / "scripts").mkdir()
        script = (ROOT / "take_screenshots.sh").read_text()
        script = script.replace("/tmp/portdeck_screenshot_config.json",
                                str(self.project / "fallback-config.json"))
        (self.project / "take_screenshots.sh").write_text(script)
        shutil.copy(ROOT / "scripts/publish_screenshot_capture.py", self.project / "scripts")
        binaries = self.project / "bin"
        binaries.mkdir()
        for name in ("xcrun", "xcodegen", "xcodebuild"):
            path = binaries / name
            path.write_text(MOCK_TOOL)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                                MOCK_SCREENS=json.dumps(CURRENT))
        for device in DEVICES:
            self.seed("en", device, HISTORICAL)
            self.seed("fr", device, ["unrelated"])

    def seed(self, locale, device, names):
        directory = self.project / "screenshots" / locale / device
        directory.mkdir(parents=True, exist_ok=True)
        for name in names:
            (directory / f"{name}.png").write_bytes(b"previous image")

    def snapshot(self):
        return {str(path.relative_to(self.project)): path.read_bytes()
                for path in (self.project / "screenshots").rglob("*.png")}

    def run_capture(self, *arguments, outcome="success"):
        result = subprocess.run(["bash", str(self.project / "take_screenshots.sh"), *arguments],
                                cwd=self.project, env=dict(self.environment, MOCK_CAPTURE=outcome),
                                capture_output=True, text=True)
        self.assertEqual(list((self.project / "screenshots").glob(".capture.*")), [])
        self.assertFalse((self.project / ".screenshot_config.json").exists())
        self.assertFalse((self.project / "fallback-config.json").exists())
        return result

    def assert_current(self, device):
        directory = self.project / "screenshots/en" / device
        self.assertEqual(sorted(path.stem for path in directory.glob("*.png")), sorted(CURRENT))
        self.assertTrue(all(path.read_bytes() == b"fresh image" for path in directory.glob("*.png")))

    def test_full_capture_retires_old_images_and_uploads_only_fresh_set(self):
        self.assertEqual(len(CURRENT), 8)
        result = self.run_capture()
        self.assertEqual(result.returncode, 0, result.stderr)
        for device in DEVICES:
            self.assert_current(device)
        listing = load_module("listing", ROOT / "scripts/update_app_store_listing.py")
        uploaded = []

        class FakeClient:
            def get(self, *args):
                return {"data": []}

            def patch(self, *args):
                pass

        def upload(client, set_id, path):
            uploaded.append(path)
            return {"id": path.stem}

        with patch.object(listing, "create_screenshot_set", return_value={"id": "set"}), \
                patch.object(listing, "upload_screenshot", side_effect=upload):
            listing.upload_screenshot_sets(FakeClient(), "locale", self.project, False)
        self.assertEqual(len(uploaded), 16)
        self.assertEqual({path.stem for path in uploaded}, set(CURRENT))

    def test_device_only_capture_preserves_other_device_and_locale(self):
        for option, changed, untouched in (("--iphone-only", DEVICES[0], DEVICES[1]),
                                          ("--ipad-only", DEVICES[1], DEVICES[0])):
            with self.subTest(option=option):
                before = self.snapshot()
                result = self.run_capture(option)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_current(changed)
                protected = {key: value for key, value in before.items()
                             if f"/en/{untouched}/" in key or "/fr/" in key}
                self.assertEqual({key: self.snapshot()[key] for key in protected}, protected)

    def test_failed_partial_capture_preserves_previous_set(self):
        before = self.snapshot()
        result = self.run_capture("--iphone-only", outcome="fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_success_without_artifacts_is_rejected(self):
        before = self.snapshot()
        result = self.run_capture("--ipad-only", outcome="empty")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_targeted_capture_updates_one_image_only(self):
        before = self.snapshot()
        result = self.run_capture("--iphone-only", "--screen", "03_capture")
        self.assertEqual(result.returncode, 0, result.stderr)
        before["screenshots/en/iphone_6.9/03_capture.png"] = b"fresh image"
        self.assertEqual(self.snapshot(), before)

    def test_unknown_target_preserves_published_images(self):
        before = self.snapshot()
        result = self.run_capture("--iphone-only", "--screen", "unknown")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_failed_directory_publication_restores_previous_set(self):
        publisher = load_module("publisher", ROOT / "scripts/publish_screenshot_capture.py")
        capture = self.project / "screenshots/.capture.failure"
        staged = capture / "en" / DEVICES[0]
        staged.mkdir(parents=True)
        (staged / "new.png").write_bytes(b"new")
        previous = self.snapshot()
        previous.pop("screenshots/.capture.failure/en/iphone_6.9/new.png")
        replace = os.replace

        def fail_publish(source, destination):
            if source == staged:
                raise OSError("simulated rename failure")
            replace(source, destination)

        with patch.object(publisher.os, "replace", side_effect=fail_publish):
            with self.assertRaises(OSError):
                publisher.publish_capture(capture, self.project / "screenshots", DEVICES[0])
        shutil.rmtree(capture)
        self.assertEqual(self.snapshot(), previous)


if __name__ == "__main__":
    unittest.main()
