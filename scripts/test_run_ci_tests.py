import copy
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run_ci_tests as ci


def results():
    bundles = []
    for bundle, names in (("PortDeckTests", ci.NATIVE_TESTS), ("PortDeckUITests", ci.UI_TESTS)):
        suites = {}
        for name in names:
            suite, method = name.split("/")
            suites.setdefault(suite, []).append({"nodeType": "Test Case", "name": method, "result": "Passed", "durationInSeconds": 0.1})
        bundles.append({"nodeType": "Unit test bundle" if bundle == "PortDeckTests" else "UI test bundle", "name": bundle,
                        "children": [{"nodeType": "Test Suite", "name": suite, "children": cases} for suite, cases in suites.items()]})
    return {"failedTests": 0, "skippedTests": 0, "passedTests": 6, "totalTestCount": 6}, {"testNodes": bundles}


class CoverageGateTests(unittest.TestCase):
    def test_accepts_explicit_native_and_ui_passes(self):
        summary, tree = results()
        self.assertEqual(len(ci.verify_results(summary, tree)), 6)

    def test_rejects_missing_native_even_when_aggregate_counts_pass(self):
        summary, tree = results()
        tree["testNodes"][0]["children"][0]["children"][0]["name"] = "testUnrelated()"
        with self.assertRaisesRegex(ValueError, "Required test did not pass"):
            ci.verify_results(summary, tree)

    def test_rejects_skip_failure_and_missing_ui(self):
        summary, tree = results()
        for result in ("Skipped", "Failed", "Expected Failure"):
            changed = copy.deepcopy(tree)
            changed["testNodes"][0]["children"][0]["children"][0]["result"] = result
            with self.subTest(result=result), self.assertRaises(ValueError):
                ci.verify_results(summary, changed)
        tree["testNodes"][1]["children"][0]["children"].pop()
        with self.assertRaises(ValueError):
            ci.verify_results(summary, tree)
        summary["skippedTests"] = 1
        with self.assertRaises(ValueError):
            ci.verify_results(summary, tree)

    def test_rejects_duplicate_or_inconsistent_results(self):
        summary, tree = results()
        tree["testNodes"].append(tree["testNodes"][0])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            ci.verify_results(summary, tree)
        summary, tree = results()
        summary["totalTestCount"] = summary["passedTests"] = 7
        with self.assertRaisesRegex(ValueError, "disagree"):
            ci.verify_results(summary, tree)


class PhaseTests(unittest.TestCase):
    def test_failed_command_retains_status_and_log(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(ci, "EVIDENCE", Path(directory)):
            metrics = {}
            with self.assertRaises(subprocess.CalledProcessError):
                ci.run_phase("failure", ["/bin/sh", "-c", "echo diagnostic; exit 7"], 5, metrics)
            self.assertEqual(metrics["failure"]["status"], "failed")
            self.assertEqual((Path(directory) / "failure.log").read_text(), "diagnostic\n")

    def test_timeout_is_bounded_and_recorded(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(ci, "EVIDENCE", Path(directory)):
            metrics = {}
            with self.assertRaises(subprocess.TimeoutExpired):
                ci.run_phase("timeout", ["/bin/sleep", "30"], 0.01, metrics)
            self.assertEqual(metrics["timeout"]["status"], "timed out")
            self.assertLess(metrics["timeout"]["seconds"], 5)


if __name__ == "__main__":
    unittest.main()
