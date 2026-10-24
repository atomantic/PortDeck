#!/usr/bin/env python3
"""Publish a successfully completed, isolated English screenshot capture."""

from pathlib import Path
import os
import sys


def publish_capture(capture: Path, output: Path, device: str, target: str = "") -> int:
    staged = capture / "en" / device
    images = sorted(staged.glob("*.png"))
    if not images or any(not path.is_file() or path.stat().st_size == 0 for path in images):
        raise RuntimeError(f"Capture produced no usable screenshot set in {staged}")
    if target and [path.name for path in images] != [f"{target}.png"]:
        raise RuntimeError(f"Capture did not produce only the requested screen: {target}")

    published = output / "en" / device
    published.parent.mkdir(parents=True, exist_ok=True)
    if target:
        published.mkdir(exist_ok=True)
        os.replace(images[0], published / images[0].name)
    else:
        # Keep the old set until the fresh directory is in place, and restore it
        # if publication fails. The caller removes the capture and backup on exit.
        backup = capture / "previous"
        had_previous = published.exists()
        if had_previous:
            os.replace(published, backup)
        try:
            os.replace(staged, published)
        except OSError:
            if had_previous:
                os.replace(backup, published)
            raise
    return len(images)


if __name__ == "__main__":
    print(publish_capture(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]))
