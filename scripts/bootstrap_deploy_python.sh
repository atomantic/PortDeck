#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/.venv-deploy"
if [ ! -x "$VENV/bin/python3" ]; then
    python3 -m venv "$VENV" >&2
fi
# Check the declared version and import before paying for a package-index request.
if ! "$VENV/bin/python3" - "$ROOT/requirements-deploy.txt" <<'CHECK'
import sys
from pathlib import Path
from importlib.metadata import version
try:
    from PIL import Image
except ImportError:
    sys.exit(1)
expected = next(line.split("==", 1)[1] for line in Path(sys.argv[1]).read_text().splitlines() if line.startswith("Pillow=="))
assert version("Pillow") == expected
CHECK
then
    "$VENV/bin/python3" -m pip install --disable-pip-version-check --only-binary=:all: -r "$ROOT/requirements-deploy.txt" >&2
fi
printf '%s\n' "$VENV/bin/python3"
