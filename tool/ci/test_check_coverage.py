"""Tests for the LCOV line-coverage gate (#301)."""

from __future__ import annotations

import io
import json
import os
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory

import check_coverage as gate

LCOV = """\
SF:lib/a.dart
DA:1,1
DA:2,0
DA:3,4
DA:4,0
LF:4
LH:2
end_of_record
SF:/home/runner/work/flutter-blog/flutter-blog/lib/b.dart
DA:1,1
DA:2,1
end_of_record
SF:lib/l10n/app_localizations.dart
DA:1,0
DA:2,0
DA:3,0
end_of_record
"""


class ParseTest(unittest.TestCase):
    def test_paths_are_repository_relative(self) -> None:
        files = gate.parse_lcov(LCOV)
        self.assertEqual(
            sorted(files), ["lib/a.dart", "lib/b.dart", "lib/l10n/app_localizations.dart"]
        )

    def test_repeated_records_merge_by_maximum_hits(self) -> None:
        text = (
            "SF:lib/a.dart\nDA:1,0\nDA:2,3\nend_of_record\n"
            "SF:lib/a.dart\nDA:1,2\nDA:2,0\nDA:3,0\nend_of_record\n"
        )
        self.assertEqual(gate.parse_lcov(text), {"lib/a.dart": {1: 2, 2: 3, 3: 0}})

    def test_malformed_data_line_is_an_error(self) -> None:
        with self.assertRaises(gate.CoverageError):
            gate.parse_lcov("SF:lib/a.dart\nDA:x,1\nend_of_record\n")

    def test_data_outside_a_file_block_is_an_error(self) -> None:
        with self.assertRaises(gate.CoverageError):
            gate.parse_lcov("DA:1,1\n")


class SummaryTest(unittest.TestCase):
    def test_exclusions_are_applied_before_the_percentage(self) -> None:
        summary = gate.summarise(gate.parse_lcov(LCOV), ("lib/l10n/*",))
        self.assertEqual((summary.hit, summary.found), (4, 6))
        self.assertAlmostEqual(summary.percent, 66.6666, places=3)

    def test_without_exclusions_generated_code_counts(self) -> None:
        summary = gate.summarise(gate.parse_lcov(LCOV), ())
        self.assertEqual((summary.hit, summary.found), (4, 9))

    def test_everything_excluded_is_an_error(self) -> None:
        with self.assertRaises(gate.CoverageError):
            gate.summarise(gate.parse_lcov(LCOV), ("lib/*",))

    def test_lowest_files_ignores_tiny_files(self) -> None:
        lines = {i: (1 if i <= 3 else 0) for i in range(1, 13)}
        files = {"lib/big.dart": lines, "lib/tiny.dart": {1: 0}}
        summary = gate.summarise(files, ())
        self.assertEqual([item.path for item in gate.lowest_files(summary)], ["lib/big.dart"])


class ThresholdTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write_config(self, payload: object) -> Path:
        path = self.root / "threshold.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_valid_configuration(self) -> None:
        threshold = gate.load_threshold(
            self.write_config({"minimum_line_coverage": 55.5, "exclude": ["lib/l10n/*"]})
        )
        self.assertEqual(threshold, gate.Threshold(55.5, ("lib/l10n/*",)))

    def test_invalid_configurations_are_rejected(self) -> None:
        for payload in (
            [],
            {},
            {"minimum_line_coverage": "60"},
            {"minimum_line_coverage": True},
            {"minimum_line_coverage": 101},
            {"minimum_line_coverage": 50, "exclude": "lib/l10n/*"},
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(gate.CoverageError):
                    gate.load_threshold(self.write_config(payload))

    def test_the_repository_configuration_is_valid(self) -> None:
        threshold = gate.load_threshold(gate.DEFAULT_CONFIG)
        self.assertGreater(threshold.minimum, 0)
        self.assertIn("lib/l10n/app_localizations*.dart", threshold.exclude)


class MainTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.lcov = self.root / "lcov.info"
        self.lcov.write_text(LCOV, encoding="utf-8")
        self.config = self.root / "threshold.json"
        self._summary = os.environ.pop("GITHUB_STEP_SUMMARY", None)

    def tearDown(self) -> None:
        if self._summary is not None:
            os.environ["GITHUB_STEP_SUMMARY"] = self._summary
        self._tmp.cleanup()

    def run_gate(self, minimum: float, *extra: str) -> tuple[int, str]:
        self.config.write_text(
            json.dumps({"minimum_line_coverage": minimum, "exclude": ["lib/l10n/*"]}),
            encoding="utf-8",
        )
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = gate.main(["--lcov", str(self.lcov), "--config", str(self.config), *extra])
        return code, out.getvalue() + err.getvalue()

    def test_coverage_at_or_above_the_floor_passes(self) -> None:
        code, output = self.run_gate(66.0)
        self.assertEqual(code, 0)
        self.assertIn("::notice title=Line coverage::line coverage 66.67%", output)

    def test_a_drop_below_the_floor_fails(self) -> None:
        code, output = self.run_gate(70.0)
        self.assertEqual(code, 1)
        self.assertIn("::error title=Coverage below floor::", output)
        self.assertIn("do not lower", output)

    def test_command_line_override_wins(self) -> None:
        code, _ = self.run_gate(10.0, "--min", "90")
        self.assertEqual(code, 1)

    def test_missing_lcov_is_a_distinct_failure(self) -> None:
        self.lcov.unlink()
        code, output = self.run_gate(10.0)
        self.assertEqual(code, 2)
        self.assertIn("LCOV file not found", output)

    def test_step_summary_lists_the_result(self) -> None:
        summary = self.root / "summary.md"
        os.environ["GITHUB_STEP_SUMMARY"] = str(summary)
        try:
            code, _ = self.run_gate(50.0)
        finally:
            del os.environ["GITHUB_STEP_SUMMARY"]
        self.assertEqual(code, 0)
        self.assertIn("meets the floor of 50.00%", summary.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
