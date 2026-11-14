#!/usr/bin/env python3
"""Build a versioned local preview or a verified notarized candidate."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile

from VerifyApp import verify


def run(arguments, output=None, environment=None):
    result = subprocess.run(arguments, capture_output=True, text=True, env=environment)
    if output:
        Path(output).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError("{} failed with exit {}".format(arguments[0], result.returncode))
    return result.stdout


def source_state(source):
    top = subprocess.run(["git", "-C", str(source), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode or Path(top.stdout.strip()).resolve() != source:
        return {"commit": None, "dirty": True}
    return {"commit": run(["git", "-C", str(source), "rev-parse", "HEAD"]).strip(),
            "dirty": bool(run(["git", "-C", str(source), "status", "--porcelain"]).strip())}


def preflight(source, mode):
    if mode == "local-preview":
        return {}
    names = ["INSOMAC_SIGNING_IDENTITY", "INSOMAC_TEAM_ID", "INSOMAC_NOTARY_PROFILE"]
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Notarized release prerequisites are missing: " + ", ".join(missing))
    identity, team, profile = [os.environ[name] for name in names]
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", identity) or not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise RuntimeError("Use a certificate SHA-1 identity and a ten-character Developer team ID.")
    identities = run(["security", "find-identity", "-v", "-p", "codesigning"])
    matching = [line for line in identities.splitlines() if identity.upper() in line.upper()]
    if not any("Developer ID Application:" in line and "(" + team + ")" in line for line in matching):
        raise RuntimeError("The selected valid Developer ID Application identity is not available for this team.")
    if source_state(source)["dirty"]:
        raise RuntimeError("Notarized candidates require a clean committed checkout.")
    # A Keychain profile reference keeps credentials out of arguments and logs.
    run(["xcrun", "notarytool", "history", "--keychain-profile", profile, "--output-format", "json"])
    return {"identity": identity, "team": team, "profile": profile}


def read_inputs(source):
    paths = []
    for folder in ["Sources", "Resources"]:
        for path in sorted((source / folder).rglob("*")):
            if path.is_file():
                paths.append(path)
    paths += [source / path for path in ["scripts/build.sh", "scripts/release.sh", "Tools/VerifyApp.py", "Tools/Release.py"]]
    contents = {}
    metadata = {}
    for path in sorted(paths):
        if path.is_symlink():
            raise RuntimeError("Release inputs must be regular files, not symlinks.")
        relative = path.relative_to(source).as_posix()
        data = path.read_bytes()
        contents[relative] = data
        metadata[relative] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                              "mode": stat.S_IMODE(path.stat().st_mode)}
    return contents, metadata


def capture_inputs(source, destination, mode):
    identity = source_state(source)
    if mode == "notarized" and identity["dirty"]:
        raise RuntimeError("Notarized candidates require a clean source snapshot.")
    contents, metadata = read_inputs(source)
    frozen = destination / ".source-inputs"
    for relative, data in contents.items():
        target = frozen / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(metadata[relative]["mode"])
    captured = {"identity": identity, "inputs": metadata,
                "sha256": hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()}
    assert_inputs_unchanged(source, captured, mode)
    return frozen, captured, contents


def assert_inputs_unchanged(source, captured, mode):
    identity = source_state(source)
    if identity != captured["identity"] or (mode == "notarized" and identity["dirty"]):
        raise RuntimeError("The source checkout identity or clean state changed during packaging.")
    if read_inputs(source)[1] != captured["inputs"]:
        raise RuntimeError("A source or build input changed during packaging.")


def package(source, mode, destination):
    credentials = preflight(source, mode)
    if destination.exists() and any(destination.iterdir()):
        raise RuntimeError("Use an empty release output directory; existing evidence is preserved.")
    destination.mkdir(parents=True, exist_ok=True)
    frozen, captured, contents = capture_inputs(source, destination, mode)
    info = plistlib.loads(contents["Resources/Info.plist"])
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise RuntimeError("The bundle version must use three numeric components.")
    environment = os.environ.copy()
    environment["INSOMAC_BUILD_DIR"] = str(destination / "build")
    run([str(frozen / "scripts/build.sh")], destination / "build.log", environment)
    assert_inputs_unchanged(source, captured, mode)
    app = destination / "build/InsoMac.app"
    verified = verify(app, expected_info=info)
    submission = None
    if mode == "notarized":
        run(["codesign", "--force", "--options", "runtime", "--timestamp", "--sign", credentials["identity"], str(app)], destination / "signing.log")
        verify(app, "developer-id", credentials["team"], expected_info=info)
        upload = destination / "notary-upload.zip"
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(upload)])
        raw = run(["xcrun", "notarytool", "submit", str(upload), "--keychain-profile", credentials["profile"],
                   "--wait", "--timeout", "15m", "--output-format", "json"], destination / "notarization.json")
        submission = json.loads(raw)
        if submission.get("status") != "Accepted" or not submission.get("id"):
            raise RuntimeError("Apple did not accept this notarization submission.")
        run(["xcrun", "notarytool", "log", submission["id"], "--keychain-profile", credentials["profile"],
             str(destination / "notary-log.json")])
        log = json.loads((destination / "notary-log.json").read_text())
        if log.get("status") != "Accepted" or any(issue.get("severity") == "error" for issue in log.get("issues", []) or []):
            raise RuntimeError("The notarization log reports an error.")
        run(["xcrun", "stapler", "staple", str(app)], destination / "stapling.log")
        assert_inputs_unchanged(source, captured, mode)
        verified = verify(app, "developer-id", credentials["team"], notarized=True, expected_info=info)
        upload.unlink()
    label = "local-preview-" if mode == "local-preview" else "notarized-candidate-"
    assert_inputs_unchanged(source, captured, mode)
    archive = destination / ("InsoMac-" + version + "-" + label + "universal.zip")
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)])
    with zipfile.ZipFile(archive) as container:
        if container.testzip() is not None:
            raise RuntimeError("The release ZIP failed its checksum test.")
        if any(not item.filename.startswith(("InsoMac.app/", "__MACOSX/")) for item in container.infolist()):
            raise RuntimeError("The release ZIP contains an unexpected top-level path.")
    with tempfile.TemporaryDirectory(prefix=".archive-check-", dir=destination) as temporary:
        run(["ditto", "-x", "-k", str(archive), temporary])
        verify(Path(temporary) / "InsoMac.app", "adhoc" if mode == "local-preview" else "developer-id",
               credentials.get("team"), notarized=mode == "notarized", expected_info=info)
    assert_inputs_unchanged(source, captured, mode)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / "SHA256SUMS").write_text(checksum + "  " + archive.name + "\n")
    metadata = {"mode": mode, "production_release": False, "version": version,
                "source": captured["identity"], "build_inputs_sha256": captured["sha256"],
                "build_inputs": captured["inputs"],
                "toolchain": run(["xcrun", "swift", "--version"]).strip(),
                "sdk": run(["xcrun", "--sdk", "macosx", "--show-sdk-version"]).strip(),
                "bundle": verified, "archive": archive.name, "archive_bytes": archive.stat().st_size,
                "archive_sha256": checksum, "notarization": submission,
                "product_acceptance": {"closed_lid_physical_panel": "unverified", "computer_use": "unverified"}}
    assert_inputs_unchanged(source, captured, mode)
    (destination / "release-manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    status = "Ad-hoc signed for local review. Not Developer ID signed or notarized." if mode == "local-preview" else "Developer ID signed, notarized, stapled, and assessed. Candidate only."
    notes = """# InsoMac {version} candidate

{status}

This candidate provides a native menu bar keep-awake switch and an experimental 1280 × 720 virtual display mode. It starts off; switching mode stops the current session.

Closed-lid physical-panel illumination and actual Codex capture/input remain unverified. Existing clients can miss newly created display modes. A running process or active display ID is not evidence of fresh GUI rendering. This candidate does not complete those product requirements.

macOS 13 is the deployment target. Runtime coverage must be read from the recorded CI and QA evidence; compilation is not a macOS 13 runtime test. No installer, privileged helper, login registration, or power-setting change is included.

Archive: `{archive}`. SHA-256: `{checksum}`. See `release-manifest.json` for source and toolchain provenance. This packaging command does not publish a GitHub release.
""".format(version=version, status=status, archive=archive.name, checksum=checksum)
    (destination / "RELEASE_NOTES.md").write_text(notes)
    return {"directory": str(destination), "archive": archive.name, "sha256": checksum, "mode": mode}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["local-preview", "notarized"], required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    try:
        if args.preflight_only:
            preflight(source, args.mode)
            print(json.dumps({"mode": args.mode, "prerequisites": "ready"}))
            return
        destination = args.output or source / "build/releases" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        print(json.dumps(package(source, args.mode, destination.resolve()), indent=2))
    except (RuntimeError, OSError, subprocess.SubprocessError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, "Release blocked: {}\n".format(error))


if __name__ == "__main__":
    main()
