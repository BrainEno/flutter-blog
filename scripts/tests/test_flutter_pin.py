"""The pinned Flutter version lives in one file; CI, scripts and docs must agree."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIN_FILE = ROOT / "tool/flutter_version.txt"


@unittest.skipIf(__import__("os").name == "nt", "Path/regex checks run on Unix shell runners")
class FlutterPinTests(unittest.TestCase):
    def setUp(self):
        self.pinned = PIN_FILE.read_text(encoding="utf-8").strip()

    def test_pin_looks_like_a_version(self):
        self.assertRegex(self.pinned, r"^\d+\.\d+\.\d+$")

    def test_every_workflow_builds_with_the_pinned_version(self):
        offenders = []
        for workflow in sorted((ROOT / ".github/workflows").glob("*.yml")):
            text = workflow.read_text(encoding="utf-8")
            for match in re.finditer(
                r'(?:FLUTTER_VERSION|flutter-version):\s*["\']?([^"\'\s#]+)', text
            ):
                value = match.group(1)
                # An indirection is valid only when the workflow defines the variable.
                if value.startswith("${{"):
                    continue
                if value != self.pinned:
                    offenders.append(f"{workflow.name}: {value}")
            if "env.FLUTTER_VERSION" in text and not re.search(
                r"^\s*FLUTTER_VERSION:", text, re.MULTILINE
            ):
                offenders.append(f"{workflow.name}: reads env.FLUTTER_VERSION without defining it")
        self.assertEqual(offenders, [], "CI must build with the pinned Flutter SDK")

    def test_local_scripts_read_the_pin_instead_of_hardcoding_it(self):
        for name in ("scripts/lib/common.sh", "scripts/run_android.ps1"):
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertIn("flutter_version.txt", text, f"{name} must read the pin")
            self.assertNotIn(
                self.pinned, text, f"{name} must not hardcode the pinned version"
            )

    def test_docs_still_name_the_pinned_version(self):
        for name in ("README.md", "AGENTS.md"):
            self.assertIn(
                self.pinned,
                (ROOT / name).read_text(encoding="utf-8"),
                f"{name} must state the pinned Flutter version",
            )


if __name__ == "__main__":
    unittest.main()
