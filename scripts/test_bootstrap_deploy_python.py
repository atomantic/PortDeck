"""Exercise the bootstrap CLI with real isolated venvs and an offline fixture wheel."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="portdeck-python-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("bootstrap_deploy_python.sh", "bootstrap_deploy_python.py"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        (self.root / "requirements-deploy.txt").write_text("Pillow==13.0.0\n")
        self.wheels = self.root / "wheels"
        self.wheels.mkdir()
        # Only bootstrap/import/metadata behavior is under test; real image conversion has its own regression.
        with zipfile.ZipFile(self.wheels / "pillow-13.0.0-py3-none-any.whl", "w") as wheel:
            for name, content in {
                "PIL/__init__.py": "",
                "PIL/Image.py": "",
                "pillow-13.0.0.dist-info/METADATA": "Metadata-Version: 2.1\nName: Pillow\nVersion: 13.0.0\nRequires-Python: >=3.11\n",
                "pillow-13.0.0.dist-info/WHEEL": "Wheel-Version: 1.0\nGenerator: fixture\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
                "pillow-13.0.0.dist-info/RECORD": "",
            }.items():
                wheel.writestr(name, content)
        self.environment = dict(os.environ, PORTDECK_DEPLOY_PYTHON=sys._base_executable,
                                PIP_CONFIG_FILE=os.devnull, PIP_NO_INDEX="1",
                                PIP_FIND_LINKS=str(self.wheels), PIP_NO_CACHE_DIR="1")

    def run_bootstrap(self, **environment):
        return subprocess.run([str(self.root / "scripts/bootstrap_deploy_python.sh")],
                              env=dict(self.environment, **environment), capture_output=True, text=True)

    def legacy_environment(self):
        venv = self.root / ".venv-deploy"
        (venv / "bin").mkdir(parents=True)
        (venv / "pyvenv.cfg").write_text("home = legacy-fixture\n")
        (venv / "sentinel").write_text("preserve until replacement succeeds")
        python = venv / "bin/python3"
        python.write_text("#!/bin/sh\nprintf '%s\\n' '" + json.dumps({"version": [3, 9], "base": "/legacy/python3"}) + "'\n")
        python.chmod(0o755)
        return venv

    def assert_environment(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        python = self.root / ".venv-deploy/bin/python3"
        self.assertEqual(result.stdout.strip(), str(python))
        probe = subprocess.run([str(python), "-c", "from PIL import Image; from importlib.metadata import version; print(version('Pillow'))"],
                               capture_output=True, text=True, check=True)
        self.assertEqual(probe.stdout.strip(), "13.0.0")
        self.assertEqual(list(self.root.glob(".venv-deploy-backup.*")), [])

    def test_fresh_environment_and_offline_reuse_have_working_console_scripts(self):
        self.assert_environment(self.run_bootstrap())
        config = self.root / ".venv-deploy/pyvenv.cfg"
        original = config.stat().st_mtime_ns
        shutil.rmtree(self.wheels)
        self.assert_environment(self.run_bootstrap())
        self.assertEqual(config.stat().st_mtime_ns, original)
        subprocess.run([str(self.root / ".venv-deploy/bin/pip"), "--version"], check=True, capture_output=True)

    def test_legacy_interpreter_is_replaced_only_with_verified_supported_environment(self):
        venv = self.legacy_environment()
        self.assert_environment(self.run_bootstrap())
        self.assertFalse((venv / "sentinel").exists())

    def test_install_failure_restores_the_previous_environment(self):
        venv = self.legacy_environment()
        original = (venv / "bin/python3").read_bytes()
        shutil.rmtree(self.wheels)
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((venv / "bin/python3").read_bytes(), original)
        self.assertTrue((venv / "sentinel").is_file())
        self.assertEqual(list(self.root.glob(".venv-deploy-backup.*")), [])

    def test_unsupported_explicit_interpreter_fails_before_mutating_existing_environment(self):
        venv = self.legacy_environment()
        result = self.run_bootstrap(PORTDECK_DEPLOY_PYTHON=str(venv / "bin/python3"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Requires Python 3.11", result.stderr)
        self.assertIn("PORTDECK_DEPLOY_PYTHON", result.stderr)
        self.assertTrue((venv / "sentinel").is_file())

    def test_unrecognized_directory_and_concurrent_bootstrap_are_preserved(self):
        venv = self.root / ".venv-deploy"
        venv.mkdir()
        marker = venv / "unrelated"
        marker.write_text("leave intact")
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unrecognized", result.stderr)
        self.assertEqual(marker.read_text(), "leave intact")
        external = self.root / "external-cache"
        venv.rename(external)
        venv.symlink_to(external, target_is_directory=True)
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlinked", result.stderr)
        self.assertEqual((external / "unrelated").read_text(), "leave intact")
        with (self.root / ".venv-deploy.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("in progress", result.stderr)
