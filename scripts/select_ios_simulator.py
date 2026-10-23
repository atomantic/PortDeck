#!/usr/bin/env python3
"""Select an available iPhone by UUID for CI's active Xcode installation."""

import json
import subprocess


def select_ios_simulator(device_groups):
    prefix = "com.apple.CoreSimulator.SimRuntime.iOS-"
    runtimes = sorted(
        (runtime for runtime in device_groups if runtime.startswith(prefix)),
        key=lambda runtime: tuple(int(part) for part in runtime[len(prefix):].split("-")),
        reverse=True,
    )
    for runtime in runtimes:
        for device in device_groups[runtime]:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                return device["udid"]
    raise ValueError("No available iPhone simulator found")


if __name__ == "__main__":
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
    ))
    try:
        print(select_ios_simulator(inventory["devices"]))
    except ValueError as error:
        raise SystemExit(str(error)) from error
