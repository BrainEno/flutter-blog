"""Tests for the core/feature dependency-rule check (#107)."""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import check_core_dependencies as checker


class CoreDependencyRuleTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "lib" / "core" / "storage").mkdir(parents=True)
        (self.root / "lib" / "core" / "storage" / "legacy").mkdir(parents=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_clean_core_reports_nothing(self) -> None:
        self.write(
            "lib/core/storage/store.dart",
            "import 'dart:async';\n"
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:belog/core/storage/app_database.dart';\n",
        )
        self.assertEqual(checker.scan(self.root), [])

    def test_feature_import_is_rejected(self) -> None:
        self.write(
            "lib/core/storage/cache.dart",
            "import 'package:belog/features/blog/data/models/blog_model.dart';\n",
        )
        problems = checker.scan(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("imports lib/features", problems[0])
        self.assertIn("lib/core/storage/cache.dart", problems[0])

    def test_flutter_ui_import_in_storage_is_rejected(self) -> None:
        self.write(
            "lib/core/storage/theme.dart",
            "import 'package:flutter/material.dart';\n",
        )
        problems = checker.scan(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("Flutter UI library", problems[0])

    def test_flutter_foundation_is_allowed_in_storage(self) -> None:
        self.write(
            "lib/core/storage/value.dart",
            "import 'package:flutter/foundation.dart';\n",
        )
        self.assertEqual(checker.scan(self.root), [])

    def test_flutter_ui_outside_storage_is_allowed(self) -> None:
        # `lib/core/theme` owns ThemeMode: that concept is allowed there.
        self.write(
            "lib/core/theme/theme_bloc.dart",
            "import 'package:flutter/material.dart';\n",
        )
        self.assertEqual(checker.scan(self.root), [])

    def test_generated_legacy_schema_is_exempt(self) -> None:
        self.write(
            "lib/core/storage/legacy/theme_preference.dart",
            "import 'package:flutter/material.dart' show ThemeMode;\n",
        )
        self.assertEqual(checker.scan(self.root), [])

    def test_missing_core_directory_is_reported(self) -> None:
        (self.root / "lib" / "core").rename(self.root / "lib" / "core-renamed")
        problems = checker.scan(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("not found", problems[0])

    def test_repository_itself_obeys_the_rule(self) -> None:
        """The real tree is the strictest fixture: it must stay clean."""
        repo_root = Path(__file__).resolve().parents[2]
        self.assertEqual(checker.scan(repo_root), [])


if __name__ == "__main__":
    unittest.main()
