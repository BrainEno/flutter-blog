#!/usr/bin/env python3
"""Enforce the layering rule between `lib/core` and the features.

`lib/core` is the shared substrate: storage, transport, theme and session
plumbing. Features depend on it, never the other way round (#107). Two rules
are checked here:

1. nothing under `lib/core` may import `package:belog/features/...`;
2. nothing under `lib/core/storage` may import a Flutter UI library
   (`material`, `widgets`, `cupertino`). `flutter/foundation.dart` and
   `dart:*` are fine - they carry no presentation concepts.

Neither rule has exemptions: after #107 retired the Isar importer there is no
generated storage code left under `lib/core/storage`.

Usage: python3 tool/ci/check_core_dependencies.py [--root DIR]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FEATURE_IMPORT = re.compile(r"""import\s+['"]package:belog/features/""")
FLUTTER_UI_IMPORT = re.compile(
    r"""import\s+['"]package:flutter/(?:material|widgets|cupertino)\.dart['"]"""
)

STORAGE_PREFIX = "lib/core/storage/"


def scan(root: Path) -> list[str]:
    """Return one human-readable line per violation under [root]."""
    problems: list[str] = []
    core = root / "lib" / "core"
    if not core.is_dir():
        return [f"{core.as_posix()}: not found (run from the repository root)"]

    for path in sorted(core.rglob("*.dart")):
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            problems.append(f"{rel}: not valid UTF-8")
            continue
        if FEATURE_IMPORT.search(text):
            problems.append(
                f"{rel}: imports lib/features - core must not depend on a "
                "feature (move the adapter into the feature)"
            )
        if not rel.startswith(STORAGE_PREFIX):
            continue
        if FLUTTER_UI_IMPORT.search(text):
            problems.append(
                f"{rel}: imports a Flutter UI library - storage must not "
                "depend on presentation types"
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(repo_root))
    args = parser.parse_args(argv)

    problems = scan(Path(args.root))
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} dependency-rule violation(s).", file=sys.stderr)
        return 1
    print("core dependency rule holds.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
