#!/usr/bin/env python3
"""Inspect a native bundle without opening its graphical interface."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import stat
import subprocess


def command(arguments, expected=0):
    result = subprocess.run(arguments, input=b"", capture_output=True, timeout=30)
    if result.returncode != expected:
        raise RuntimeError("Command failed: {} (exit {})\n{}".format(
            arguments[0], result.returncode, result.stderr.decode(errors="replace")))
    return (result.stdout + result.stderr).decode(errors="replace")


def verify(app, signing="adhoc", team=None, runtime=False, notarized=False, expected_info=None):
    app = Path(app).resolve()
    source = Path(__file__).resolve().parents[1]
    expected = expected_info or plistlib.loads((source / "Resources/Info.plist").read_bytes())
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable",
                "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
                "LSMinimumSystemVersion", "LSUIElement"]:
        if info.get(key) != expected[key]:
            raise RuntimeError("Unexpected bundle metadata: " + key)
    binary = app / "Contents/MacOS/InsoMac"
    if not binary.is_file() or stat.S_IMODE(binary.stat().st_mode) != 0o755:
        raise RuntimeError("The InsoMac executable must have mode 0755.")
    architectures = command(["xcrun", "lipo", "-archs", str(binary)]).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise RuntimeError("The bundle must contain arm64 and x86_64.")
    for architecture in architectures:
        data = command(["xcrun", "vtool", "-arch", architecture, "-show-build", str(binary)])
        if not re.search(r"\bminos\s+13\.0\b", data) or "MACOS" not in data:
            raise RuntimeError("Invalid deployment metadata for " + architecture)
    command(["codesign", "--verify", "--strict", str(app)])
    signature = command(["codesign", "-dv", "--verbose=4", str(app)])
    if not re.search(r"^Identifier=" + re.escape(info["CFBundleIdentifier"]) + r"$", signature, re.MULTILINE):
        raise RuntimeError("Signature and bundle identifiers differ.")
    if signing == "adhoc":
        if "Signature=adhoc" not in signature:
            raise RuntimeError("Expected an explicitly ad-hoc local preview.")
    else:
        if not team or not re.search(r"^TeamIdentifier=" + re.escape(team) + r"$", signature, re.MULTILINE):
            raise RuntimeError("The Developer ID team does not match.")
        if "Authority=Developer ID Application:" not in signature:
            raise RuntimeError("A Developer ID Application certificate is required.")
        if not re.search(r"flags=.*\bruntime\b", signature) or "Timestamp=" not in signature:
            raise RuntimeError("Hardened runtime and a secure timestamp are required.")
    if notarized:
        if signing != "developer-id":
            raise RuntimeError("Notarized validation requires Developer ID signing.")
        command(["xcrun", "stapler", "validate", str(app)])
        command(["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)])
    result = {"name": info["CFBundleName"], "identifier": info["CFBundleIdentifier"],
              "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
              "minimum_macos": info["LSMinimumSystemVersion"], "architectures": sorted(architectures),
              "signing": signing, "notarized_and_stapled": notarized,
              "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    if runtime:
        architecture = platform.machine()
        if architecture not in architectures:
            raise RuntimeError("Unsupported native runner architecture: " + architecture)
        # The invalid parent is rejected before AppKit, assertions, or display creation.
        command(["/usr/bin/arch", "-" + architecture, str(binary), "--virtual-display-owner", "0"], expected=2)
        result["native_executable_executed"] = architecture
        result["runtime_path"] = "startup parent guard; no graphics or power resources"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--signing", choices=["adhoc", "developer-id"], default="adhoc")
    parser.add_argument("--team")
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.app, args.signing, args.team, args.runtime, args.notarized), indent=2))
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, "Bundle verification failed: {}\n".format(error))


if __name__ == "__main__":
    main()
