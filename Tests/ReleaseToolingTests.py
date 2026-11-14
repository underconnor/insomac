import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE / "Tools"))
import Release


class ReleaseSnapshotTests(unittest.TestCase):
    def fixture(self, directory):
        source = Path(directory) / "source"
        files = {"Sources/Core/Example.swift": b"before", "scripts/build.sh": b"#!/bin/bash\nexit 0\n",
                 "scripts/release.sh": b"#!/bin/bash\nexit 0\n", "Tools/VerifyApp.py": b"# verifier\n",
                 "Tools/Release.py": b"# packager\n",
                 "Resources/Info.plist": plistlib.dumps({"CFBundleShortVersionString": "0.1.0"})}
        for relative, content in files.items():
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            path.chmod(0o755 if relative.startswith("scripts/") else 0o644)
        return source

    def rejected_change(self, kind, mode="local-preview"):
        with tempfile.TemporaryDirectory(prefix="insomac-release-test-") as temporary:
            source = self.fixture(temporary)
            destination = Path(temporary) / "candidate"
            identity = {"commit": "a" * 40, "dirty": False}

            def simulated_build(arguments, output=None, environment=None):
                frozen_script = Path(arguments[0])
                self.assertNotEqual(frozen_script, source / "scripts/build.sh")
                self.assertEqual((frozen_script.parents[1] / "Sources/Core/Example.swift").read_bytes(), b"before")
                if kind == "input":
                    (source / "Sources/Core/Example.swift").write_bytes(b"concurrent edit")
                elif kind == "head":
                    identity["commit"] = "b" * 40
                else:
                    identity["dirty"] = True
                return ""

            with patch.object(Release, "preflight", return_value={}), \
                 patch.object(Release, "source_state", side_effect=lambda _: dict(identity)), \
                 patch.object(Release, "run", side_effect=simulated_build), \
                 patch.object(Release, "verify", side_effect=AssertionError("Verification must not run after provenance changes.")):
                with self.assertRaisesRegex(RuntimeError, "changed during packaging"):
                    Release.package(source, mode, destination)
            self.assertFalse((destination / "release-manifest.json").exists())
            self.assertFalse(list(destination.glob("*.zip")))

    def test_concurrent_input_edit_is_rejected_after_frozen_build(self):
        self.rejected_change("input")

    def test_concurrent_head_change_is_rejected(self):
        self.rejected_change("head")

    def test_notarized_candidate_rejects_new_dirty_state(self):
        self.rejected_change("dirty", "notarized")


if __name__ == "__main__":
    unittest.main()
