"""CLI regressions for refusing an upload with incomplete export configuration."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check_export_configuration.py")


class ExportConfigurationTests(unittest.TestCase):
    def run_check(self, settings, *, other_target=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            spec = {"targets": {"PortDeck": {"settings": settings}}}
            if other_target:
                spec["targets"]["Tests"] = other_target
            fixture = root / "spec.json"
            fixture.write_text(json.dumps(spec))
            return subprocess.run([sys.executable, str(SCRIPT), str(fixture), "--root", str(root)], capture_output=True, text=True)

    def test_current_non_exempt_declaration_requires_code(self):
        result = self.run_check({"base": {"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": True}})
        self.assertEqual(result.returncode, 1)
        self.assertIn("issue #33", result.stderr)

    def test_explicit_exempt_declaration_passes_presence_check(self):
        self.assertEqual(self.run_check({"base": {"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": False}}).returncode, 0)

    def test_release_override_requires_resolved_code_without_logging_it(self):
        settings = {"base": {"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": False}, "configs": {"Release": {"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "YES", "INFOPLIST_KEY_ITSEncryptionExportComplianceCode": "fixture-only-code"}}}
        result = self.run_check(settings)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("fixture-only-code", result.stdout + result.stderr)
        settings["configs"]["Release"]["INFOPLIST_KEY_ITSEncryptionExportComplianceCode"] = "$(MISSING)"
        self.assertEqual(self.run_check(settings).returncode, 1)

    def test_other_target_code_cannot_satisfy_app_requirement(self):
        result = self.run_check({"base": {"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": True}}, other_target={"settings": {"base": {"INFOPLIST_KEY_ITSEncryptionExportComplianceCode": "fixture-only-code"}}})
        self.assertEqual(result.returncode, 1)

    def test_missing_or_ambiguous_declaration_fails_closed(self):
        for settings in ({}, {"base": {"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "$(UNRESOLVED)"}}, {"groups": ["Shared"]}):
            with self.subTest(settings=settings):
                self.assertEqual(self.run_check(settings).returncode, 1)
