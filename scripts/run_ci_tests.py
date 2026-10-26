#!/usr/bin/env python3
"""Build one signed simulator host; retain bounded phase and coverage evidence."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from select_ios_simulator import select_ios_simulator

NATIVE_TESTS = (
    "KeychainCredentialStoreTests/testNativeDeviceOnlyRoundTripUsesUniqueServiceAndCleansUpItsOwnItems()",
    "TailcatTransportTests/testNativeTailcatKeychainRoundTrip()",
)
UI_TESTS = tuple(f"PortDeckUITests/{name}()" for name in (
    "testOfflineDemoCanBeEnteredAndExited",
    "testOfflineDemoCanBeEnteredFromSettingsWithoutLogin",
    "testDailyLogReminderSettingIsAvailable",
    "testTailcatSetupRejectsAnInvalidSecretLocally",
))
EVIDENCE = Path("build/ci-evidence")
RESULT = EVIDENCE / "tests.xcresult"


def verify_results(summary, report):
    """Aggregate counts cannot prove that the two required native tests ran."""
    if (summary["failedTests"] != 0 or summary["skippedTests"] != 0
            or summary["passedTests"] != summary["totalTestCount"]
            or summary["passedTests"] == 0):
        raise ValueError(f"Tests failed, skipped or missing: {summary}")
    cases = {}

    def walk(nodes, bundle=None, suite=None):
        for node in nodes:
            kind = node["nodeType"]
            current_bundle = node["name"] if kind in ("Unit test bundle", "UI test bundle") else bundle
            current_suite = node["name"] if kind == "Test Suite" else suite
            if kind == "Test Case":
                key = (current_bundle, f"{current_suite}/{node['name']}")
                if key in cases:
                    raise ValueError(f"Duplicate test case: {key}")
                cases[key] = node
            walk(node.get("children", []), current_bundle, current_suite)

    walk(report["testNodes"])
    for bundle, names in (("PortDeckTests", NATIVE_TESTS), ("PortDeckUITests", UI_TESTS)):
        for name in names:
            node = cases.get((bundle, name))
            if node is None or node.get("result") != "Passed":
                raise ValueError(f"Required test did not pass: {bundle}/{name}: {node}")
    if len(cases) != summary["totalTestCount"] or any(n.get("result") != "Passed" for n in cases.values()):
        raise ValueError("Test tree and summary disagree")
    return {f"{bundle}/{name}": {"result": n["result"], "seconds": n.get("durationInSeconds")}
            for (bundle, name), n in cases.items()}


def verify_test_diagnostics(log):
    if "During recovery, parent directory path reported as missing" in log:
        raise ValueError("Persistent-store parent directory was not initialized before opening the store.")


def run_phase(name, command, timeout, metrics):
    """Kill the command group on timeout; preserve raw output and report a tail."""
    log = EVIDENCE / f"{name}.log"
    started = time.monotonic()
    status = "failed"
    print(f"Starting {name} (limit {timeout}s)", flush=True)
    try:
        with log.open("w") as output:
            with subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True) as process:
                try:
                    code = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    status = "timed out"
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    raise
                if code:
                    raise subprocess.CalledProcessError(code, command)
        status = "passed"
        return log.read_text()
    finally:
        metrics[name] = {"seconds": round(time.monotonic() - started, 3), "status": status}
        print(f"{name}: {status}, {metrics[name]['seconds']}s", flush=True)
        if status != "passed" and log.exists():
            print("\n".join(log.read_text(errors="replace").splitlines()[-80:]), flush=True)


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    metrics = {"runner": {key: os.environ.get(key) for key in ("ImageOS", "ImageVersion", "RUNNER_ARCH")}}
    try:
        metrics["xcode"] = run_phase("xcode-version", ["xcodebuild", "-version"], 30, metrics).strip()
        inventory = json.loads(run_phase("simulator-inventory", ["xcrun", "simctl", "list", "devices", "available", "--json"], 30, metrics))["devices"]
        simulator = select_ios_simulator(inventory)
        device = next(d for devices in inventory.values() for d in devices if d["udid"] == simulator)
        metrics["simulator"] = {"name": device["name"], "runtime": next(r for r, devices in inventory.items() if device in devices)}
        if device["state"] != "Booted":
            run_phase("simulator-boot", ["xcrun", "simctl", "boot", simulator], 30, metrics)
        common = ["-project", "PortDeck.xcodeproj", "-scheme", "PortDeck",
                  "-destination", f"platform=iOS Simulator,id={simulator}", "-destination-timeout", "60",
                  "-configuration", "Debug", "-derivedDataPath", "build",
                  "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO",
                  "-skipPackagePluginValidation", "-skipMacroValidation"]
        build_log = run_phase("build-for-testing", ["xcodebuild", "build-for-testing", *common, "-showBuildTimingSummary"], 1200, metrics)
        # Xcode task durations are cumulative work, not a separate wall-clock phase.
        sign_times = re.findall(r"([\d.]+) seconds\s+CodeSign\b", build_log)
        metrics["codesign_task_seconds"] = sum(map(float, sign_times)) if sign_times else None
        # Cold hosted runtimes migrate data while the signed products build.
        # The baseline spent ~612s in its first test operation; 180s was too short.
        run_phase("simulator-ready", ["xcrun", "simctl", "bootstatus", simulator, "-b"], 900, metrics)
        test_log = run_phase("test-without-building", ["xcodebuild", "test-without-building", *common,
                  "-parallel-testing-enabled", "NO", "-resultBundlePath", str(RESULT),
                  "-only-testing:PortDeckTests", *[f"-only-testing:PortDeckUITests/{name.removesuffix('()')}" for name in UI_TESTS]], 900, metrics)
        # Preserve the disk-backed first-launch diagnostic gate added in #37.
        verify_test_diagnostics(test_log)
        summary = json.loads(run_phase("test-summary", ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(RESULT)], 60, metrics))
        report = json.loads(run_phase("test-tree", ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(RESULT)], 60, metrics))
        metrics["tests"] = verify_results(summary, report)
        metrics["passed_tests"] = summary["passedTests"]
        metrics["xctest_body_seconds"] = sum(n["seconds"] or 0 for n in metrics["tests"].values())
        print(f"Verified {summary['passedTests']} passed, zero skipped; both native keychain tests and all four UI smoke tests passed.", flush=True)
    finally:
        (EVIDENCE / "timings.json").write_text(json.dumps(metrics, indent=2) + "\n")
        lines = ["## Simulator test phases", "", "| Phase | Seconds | Status |", "| --- | ---: | --- |"]
        lines += [f"| {name} | {value['seconds']} | {value['status']} |" for name, value in metrics.items() if isinstance(value, dict) and "status" in value]
        lines += ["", f"CodeSign cumulative task seconds: {metrics.get('codesign_task_seconds', 'unavailable')}",
                  f"XCTest body seconds: {metrics.get('xctest_body_seconds', 'unavailable')}",
                  f"Verified passed tests (zero skips): {metrics.get('passed_tests', 'not verified')}",
                  "", "Build includes signing. Test wall time includes installation/host launch and XCTest execution; body time is reported separately.",
                  "Raw logs, per-test results and runner/Xcode/runtime metadata: ci-test-evidence artifact."]
        text = "\n".join(lines) + "\n"
        (EVIDENCE / "timings.md").write_text(text)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
                output.write(text)


if __name__ == "__main__":
    main()
