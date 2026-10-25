"""Provision only PortDeck's isolated deployment Python environment."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

SUPPORTED = "Python 3.11–3.15 (3.13 recommended)"
PROBE = "import json,sys; print(json.dumps({'version':list(sys.version_info[:2]),'base':sys._base_executable}))"


def interpreter_info(executable):
    try:
        result = subprocess.run([str(executable), "-c", PROBE], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            return json.loads(result.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return None


def supported(info):
    return info is not None and (3, 11) <= tuple(info["version"]) <= (3, 15)


def select_interpreter(override):
    candidates = [override] if override else [
        "python3.13", "/opt/homebrew/opt/python@3.13/bin/python3.13",
        "/usr/local/opt/python@3.13/bin/python3.13",
        "python3.14", "python3.15", "python3.12", "python3.11", "python3",
    ]
    for candidate in candidates:
        executable = shutil.which(candidate)
        if executable:
            info = interpreter_info(executable)
            if supported(info):
                return str(Path(info["base"]).resolve())
    raise RuntimeError(f"Requires {SUPPORTED}. Install a supported Python separately, then set "
                       "PORTDECK_DEPLOY_PYTHON to its executable. No global packages were changed.")


def healthy(python, expected):
    if not supported(interpreter_info(python)):
        return False
    check = "from importlib.metadata import version; from PIL import Image; import sys; sys.exit(version('Pillow') != sys.argv[1])"
    try:
        return subprocess.run([str(python), "-c", check, expected], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def bootstrap(root):
    venv = root / ".venv-deploy"
    python = venv / "bin/python3"
    requirements = root / "requirements-deploy.txt"
    expected = next(line.split("==", 1)[1].strip() for line in requirements.read_text().splitlines()
                    if line.startswith("Pillow=="))
    with (root / ".venv-deploy.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Another deployment Python bootstrap is in progress; wait for it to finish.") from error
        if venv.is_symlink() or (venv.exists() and not (venv / "pyvenv.cfg").is_file()):
            raise RuntimeError("Refusing to replace an unrecognized or symlinked .venv-deploy directory.")
        override = os.environ.get("PORTDECK_DEPLOY_PYTHON")
        selected = select_interpreter(override) if override else None
        existing = interpreter_info(python)
        if healthy(python, expected) and (not selected or Path(existing["base"]).resolve() == Path(selected)):
            return python
        selected = selected or select_interpreter(None)
        backup = None
        creating = False
        succeeded = False
        try:
            if venv.exists():
                backup = Path(tempfile.mkdtemp(prefix=".venv-deploy-backup.", dir=root))
                venv.rename(backup / "venv")
            creating = True
            # Create at its final path: venv console-script shebangs must not point at a staging directory.
            subprocess.run([selected, "-m", "venv", str(venv)], check=True, stdout=sys.stderr)
            subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                            "--only-binary=:all:", "-r", str(requirements)], check=True, stdout=sys.stderr)
            if not healthy(python, expected):
                raise RuntimeError("The deployment environment failed its interpreter/Pillow verification.")
            succeeded = True
        except BaseException:
            if creating and venv.exists():
                shutil.rmtree(venv)
            if backup and (backup / "venv").exists():
                try:
                    (backup / "venv").rename(venv)
                except OSError as error:
                    raise RuntimeError(f"Could not restore the previous environment; retained at {backup / 'venv'}") from error
            raise
        finally:
            # Retain the old cache if restoration itself failed.
            if backup and (succeeded or not (backup / "venv").exists()):
                shutil.rmtree(backup)
        return python


def interrupted(signum, _frame):
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    try:
        print(bootstrap(Path(__file__).resolve().parents[1]))
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Deployment Python bootstrap: {error}", file=sys.stderr)
        sys.exit(1)
