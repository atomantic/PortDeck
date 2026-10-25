#!/usr/bin/env python3
"""Check explicit release export metadata without making a legal determination."""
import argparse
import json
import plistlib
import sys
from pathlib import Path


class ConfigurationError(ValueError):
    pass


def release_settings(spec, target):
    result = {}
    for owner in (spec, target):
        if owner.get("configFiles"):
            raise ConfigurationError("Review xcconfig export metadata before extending this check.")
        settings = owner.get("settings", {})
        if settings.get("groups"):
            raise ConfigurationError("Review setting-group export metadata before extending this check.")
        result.update(settings.get("base", {}))
        for name, values in settings.get("configs", {}).items():
            if name.lower() == "release":
                result.update(values)
    return result


def check(spec, root):
    target = spec["targets"]["PortDeck"]
    settings = release_settings(spec, target)
    info = {}
    source = settings.get("INFOPLIST_FILE")
    if source:
        if "$" in str(source):
            raise ConfigurationError("Resolve INFOPLIST_FILE before checking export metadata.")
        with (root / source).open("rb") as stream:
            info.update(plistlib.load(stream))
    info.update((target.get("info") or {}).get("properties", {}))
    for key in ("ITSAppUsesNonExemptEncryption", "ITSEncryptionExportComplianceCode"):
        setting = "INFOPLIST_KEY_" + key
        if setting in settings:
            info[key] = settings[setting]
    value = info.get("ITSAppUsesNonExemptEncryption")
    if isinstance(value, str):
        value = {"YES": True, "NO": False, "true": True, "false": False}.get(value)
    if not isinstance(value, bool):
        raise ConfigurationError("Explicit ITSAppUsesNonExemptEncryption declaration is required.")
    code = info.get("ITSEncryptionExportComplianceCode")
    if value and (not isinstance(code, str) or not code.strip() or "$" in code):
        raise ConfigurationError(
            "Non-exempt encryption is declared but no resolved Apple-issued export compliance "
            "code is configured. Resolve issue #33 with the operator; do not invent a code "
            "or change the legal declaration to bypass this check."
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path, help="xcodegen dump --type json output")
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        check(json.loads(args.spec.read_text()), args.root)
    except (ConfigurationError, KeyError, TypeError, ValueError, OSError, plistlib.InvalidFileException) as error:
        print("Export configuration preflight failed: " + str(error), file=sys.stderr)
        return 1
    print("Export metadata presence check passed; legal classification and Apple approval remain operator responsibilities.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
