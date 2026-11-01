import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest


TOOL = Path(__file__).resolve().parents[2] / "tool" / "export_unclaimed_drafts.py"


@unittest.skipUnless(os.name == "posix", "export requires POSIX file permissions")
class UnclaimedDraftExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source.sqlite"
        self.output = self.root / "drafts.json"
        db = sqlite3.connect(self.source)
        db.execute(
            "CREATE TABLE drafts (id INTEGER PRIMARY KEY, blog_id TEXT, title TEXT NOT NULL, "
            "content TEXT NOT NULL, tags TEXT NOT NULL, updated_at INTEGER NOT NULL)"
        )
        db.executemany(
            "INSERT INTO drafts VALUES (?, ?, ?, ?, ?, ?)",
            [
                (1, None, "private title", "private body", 'not-json [ \"raw\" ]', 42),
                (2, "slug", "second", "contents", sqlite3.Binary(b"\xff\x00"), 43),
            ],
        )
        db.commit()
        db.close()

    def run_tool(self, source=None, output=None):
        return subprocess.run(
            [sys.executable, str(TOOL), str(source or self.source), str(output or self.output)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_export_is_read_only_private_and_preserves_raw_data(self):
        before = self.source.read_bytes()
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
        payload = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual(payload["format"], "belog-unclaimed-drafts-v1")
        self.assertEqual(payload["drafts"][0]["tags"], 'not-json [ "raw" ]')
        self.assertIsNone(payload["drafts"][0]["blog_id"])
        self.assertEqual(payload["drafts"][0]["title"], "private title")
        self.assertEqual(payload["drafts"][0]["content"], "private body")
        self.assertEqual(payload["drafts"][0]["updated_at"], 42)
        self.assertEqual(payload["drafts"][1]["tags"], {"encoding": "base64", "data": "/wA="})
        self.assertNotIn("private title", result.stdout + result.stderr)
        self.assertNotIn("private body", result.stdout + result.stderr)
        self.assertNotIn("not-json", result.stdout + result.stderr)

    def test_existing_destination_and_symlinks_are_never_overwritten(self):
        self.output.write_text("keep me", encoding="utf-8")
        self.assertNotEqual(self.run_tool().returncode, 0)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "keep me")
        link = self.root / "link.json"
        link.symlink_to(self.output)
        self.assertNotEqual(self.run_tool(output=link).returncode, 0)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "keep me")
        dangling = self.root / "dangling.json"
        dangling.symlink_to(self.root / "nonexistent")
        self.assertNotEqual(self.run_tool(output=dangling).returncode, 0)
        self.assertFalse((self.root / "nonexistent").exists())

    def test_missing_table_or_database_cannot_create_an_export(self):
        other = self.root / "empty.sqlite"
        sqlite3.connect(other).close()
        self.assertNotEqual(self.run_tool(source=other).returncode, 0)
        self.assertFalse(self.output.exists())
        missing = self.root / "missing.sqlite"
        self.assertNotEqual(self.run_tool(source=missing).returncode, 0)
        self.assertFalse(missing.exists())
        self.assertFalse(self.output.exists())

    def test_never_overwrites_the_source(self):
        before = self.source.read_bytes()
        self.assertNotEqual(self.run_tool(output=self.source).returncode, 0)
        self.assertEqual(self.source.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
