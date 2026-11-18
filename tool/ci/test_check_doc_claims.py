"""Focused fixtures for the documentation-claim gate (#290)."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


SCRIPT = Path(__file__).with_name("check_doc_claims.sh")
STATUS = "> 状态：active ｜ 最后核对：2026-11-16 @ fixture\n"


class DocumentationClaimCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "docs").mkdir()
        (self.root / "lib").mkdir()
        self.write("README.md", "# Project\n")
        self.write("lib/example.dart", "void main() {}\n")
        self.write("docs/README.md", f"# Docs\n\n{STATUS}\n[Guide](guide.md)\n")
        self.write(
            "docs/guide.md",
            f"# Guide\n\n{STATUS}\nThe implementation is `lib/example.dart`.\n",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def run_check(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), "--root", str(self.root)],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_valid_living_and_archived_documents_pass(self) -> None:
        self.write(
            "docs/archive/review.md",
            "# Historical review\n\n"
            "> 状态：archived ｜ 最后核对：2026-11-02 @ snapshot\n\n"
            "It once said the repository only had one open issue.\n",
        )
        self.write(
            "docs/README.md",
            f"# Docs\n\n{STATUS}\n[Guide](guide.md)\n[Historical](archive/review.md)\n",
        )

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Documentation index", result.stdout)

    def test_unindexed_document_is_rejected(self) -> None:
        self.write("docs/extra.md", f"# Extra\n\n{STATUS}\n")

        result = self.run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/extra.md: missing from docs/README.md index", result.stderr)

    def test_missing_status_header_is_rejected(self) -> None:
        self.write("docs/guide.md", "# Guide\n\nThe implementation is `lib/example.dart`.\n")

        result = self.run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/guide.md: missing status header", result.stderr)

    def test_live_stale_issue_claim_is_rejected(self) -> None:
        self.write("README.md", "# Project\n\n现在只剩 #18 开放。\n")

        result = self.run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("README.md: live documentation must not claim", result.stderr)

    def test_archived_status_outside_archive_is_rejected(self) -> None:
        self.write(
            "docs/guide.md",
            "# Guide\n\n"
            "> 状态：archived ｜ 最后核对：2026-11-02 @ snapshot\n",
        )

        result = self.run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/guide.md: archived documents must live under docs/archive", result.stderr)

    def test_missing_backticked_repository_path_is_rejected(self) -> None:
        self.write(
            "docs/guide.md",
            f"# Guide\n\n{STATUS}\nThe removed file was `lib/missing.dart`.\n",
        )

        result = self.run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/guide.md:", result.stderr)
        self.assertIn("referenced path does not exist: lib/missing.dart", result.stderr)


if __name__ == "__main__":
    unittest.main()
