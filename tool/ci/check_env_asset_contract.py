#!/usr/bin/env python3
"""Fail if a gitignored .env file is bundled as a Flutter asset."""

from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = ROOT / "pubspec.yaml"
GITIGNORE = ROOT / ".gitignore"

def tracked(path: str) -> bool:
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", path],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0

def main() -> int:
    if not PUBSPEC.is_file():
        print("::error::pubspec.yaml is missing.")
        return 1

    pubspec = PUBSPEC.read_text(encoding="utf-8")
    # Only consider a literal .env asset entry, not documentation/comments.
    env_asset = re.search(r"(?m)^\s{4}-\s*['\"]?\.env['\"]?\s*(?:#.*)?$", pubspec)
    errors: list[str] = []

    if env_asset:
        errors.append("pubspec.yaml bundles .env as a Flutter asset. Remove it and use explicit compile-time configuration injection (Issue #2).")

    if tracked(".env"):
        errors.append("A .env file is tracked by git. Remove it from version control and rotate any credentials that were exposed.")

    if GITIGNORE.is_file() and re.search(r"(?m)^\.env/?$", GITIGNORE.read_text(encoding="utf-8")) and env_asset:
        errors.append(".env is ignored by .gitignore but is still declared as an asset; a clean clone cannot reproduce this asset.")

    if errors:
        for error in errors:
            print(f"::error::{error}")
        return 1

    print("Environment asset contract passed: no bundled .env and no tracked .env.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
