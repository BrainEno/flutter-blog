#!/usr/bin/env python3
"""Fail CI when Flutter line coverage drops below the configured floor (#301).

`flutter test --coverage` writes `coverage/lcov.info`. This script parses it
with the standard library only, merges records that describe the same source
file (a file loaded by several test isolates can appear more than once),
drops excluded paths such as generated localizations, and compares the line
coverage percentage with the floor in `tool/ci/coverage_threshold.json`.

The floor is a ratchet against silent regressions, not a target: raise it
deliberately in a reviewed PR when coverage has grown, and never lower it to
make an unrelated change pass. Coverage is evidence, not a vanity number
(AGENTS.md).

Exit codes: 0 when coverage meets the floor, 1 when it is below the floor,
2 when the LCOV file or the configuration is missing or malformed.

Usage:
    python3 tool/ci/check_coverage.py [--lcov PATH] [--config PATH] [--min PCT]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from fnmatch import fnmatch
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LCOV = REPO_ROOT / "coverage" / "lcov.info"
DEFAULT_CONFIG = REPO_ROOT / "tool" / "ci" / "coverage_threshold.json"


class CoverageError(Exception):
    """The input cannot be evaluated (missing, malformed or empty)."""


@dataclass(frozen=True)
class Threshold:
    minimum: float
    exclude: tuple[str, ...]


@dataclass(frozen=True)
class FileCoverage:
    path: str
    found: int
    hit: int


@dataclass(frozen=True)
class Summary:
    files: tuple[FileCoverage, ...]

    @property
    def found(self) -> int:
        return sum(item.found for item in self.files)

    @property
    def hit(self) -> int:
        return sum(item.hit for item in self.files)

    @property
    def percent(self) -> float:
        return 100.0 * self.hit / self.found if self.found else 0.0


def load_threshold(path: Path) -> Threshold:
    """Reads the floor and the exclusion globs from [path]."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CoverageError(f"{path}: coverage threshold file not found") from error
    except json.JSONDecodeError as error:
        raise CoverageError(f"{path}: invalid JSON ({error.msg})") from error
    if not isinstance(raw, dict):
        raise CoverageError(f"{path}: expected a JSON object")
    minimum = raw.get("minimum_line_coverage")
    if isinstance(minimum, bool) or not isinstance(minimum, (int, float)):
        raise CoverageError(f"{path}: minimum_line_coverage must be a number")
    if not 0 <= minimum <= 100:
        raise CoverageError(f"{path}: minimum_line_coverage must be within 0..100")
    exclude = raw.get("exclude", [])
    if not isinstance(exclude, list) or not all(isinstance(p, str) for p in exclude):
        raise CoverageError(f"{path}: exclude must be a list of glob strings")
    return Threshold(minimum=float(minimum), exclude=tuple(exclude))


def _normalise(source: str) -> str:
    """Repository-relative POSIX path, whatever the runner's checkout path."""
    path = source.strip().replace("\\", "/")
    marker = "/lib/"
    if not path.startswith("lib/") and marker in path:
        path = "lib/" + path.split(marker, 1)[1]
    return path


def parse_lcov(text: str) -> dict[str, dict[int, int]]:
    """Maps each source file to `{line: hits}`, merging repeated records.

    `DA:` lines are authoritative: `LF`/`LH` totals cannot be merged when the
    same file appears twice, while per-line hits can (the maximum wins).
    """
    files: dict[str, dict[int, int]] = {}
    current: dict[int, int] | None = None
    for number, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip()
        if line.startswith("SF:"):
            current = files.setdefault(_normalise(line[3:]), {})
        elif line.startswith("DA:"):
            if current is None:
                raise CoverageError(f"line {number}: DA record outside of an SF block")
            fields = line[3:].split(",")
            try:
                line_number, hits = int(fields[0]), int(fields[1])
            except (IndexError, ValueError) as error:
                raise CoverageError(f"line {number}: malformed DA record") from error
            current[line_number] = max(hits, current.get(line_number, 0))
        elif line == "end_of_record":
            current = None
    return files


def summarise(files: dict[str, dict[int, int]], exclude: tuple[str, ...]) -> Summary:
    kept = []
    for path in sorted(files):
        if any(fnmatch(path, pattern) for pattern in exclude):
            continue
        lines = files[path]
        kept.append(
            FileCoverage(
                path=path,
                found=len(lines),
                hit=sum(1 for hits in lines.values() if hits > 0),
            )
        )
    summary = Summary(files=tuple(kept))
    if summary.found == 0:
        raise CoverageError("no instrumented lines left after exclusions")
    return summary


def lowest_files(summary: Summary, count: int = 5) -> list[FileCoverage]:
    """The least-covered files with at least ten instrumented lines."""
    candidates = [item for item in summary.files if item.found >= 10]
    return sorted(candidates, key=lambda item: (item.hit / item.found, item.path))[:count]


def _write_step_summary(summary: Summary, threshold: Threshold, passed: bool) -> None:
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if not target:
        return
    verdict = "meets" if passed else "is below"
    rows = "\n".join(
        f"| `{item.path}` | {item.hit}/{item.found} | {100.0 * item.hit / item.found:.1f}% |"
        for item in lowest_files(summary)
    )
    with open(target, "a", encoding="utf-8") as handle:
        handle.write(
            "### Line coverage\n\n"
            f"{summary.percent:.2f}% ({summary.hit}/{summary.found} lines in "
            f"{len(summary.files)} files) {verdict} the floor of "
            f"{threshold.minimum:.2f}%.\n\n"
        )
        if rows:
            handle.write(
                "| Least-covered file | Lines | Coverage |\n|---|---|---|\n" + rows + "\n"
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lcov", type=Path, default=DEFAULT_LCOV)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument(
        "--min",
        type=float,
        default=None,
        help="override the configured floor (for local experiments only)",
    )
    args = parser.parse_args(argv)

    try:
        threshold = load_threshold(args.config)
        if args.min is not None:
            threshold = Threshold(minimum=args.min, exclude=threshold.exclude)
        try:
            text = args.lcov.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise CoverageError(
                f"{args.lcov}: LCOV file not found (did `flutter test --coverage` run?)"
            ) from error
        summary = summarise(parse_lcov(text), threshold.exclude)
    except CoverageError as error:
        print(f"::error title=Coverage gate::{error}")
        return 2

    passed = summary.percent + 1e-9 >= threshold.minimum
    message = (
        f"line coverage {summary.percent:.2f}% ({summary.hit}/{summary.found} lines, "
        f"{len(summary.files)} files); floor {threshold.minimum:.2f}%"
    )
    _write_step_summary(summary, threshold, passed)
    if passed:
        print(f"::notice title=Line coverage::{message}")
        return 0
    print(f"::error title=Coverage below floor::{message}")
    for item in lowest_files(summary):
        print(f"  {item.path}: {item.hit}/{item.found}")
    print(
        "Add meaningful tests for the code this change touches; do not lower "
        "tool/ci/coverage_threshold.json to make the check pass.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
