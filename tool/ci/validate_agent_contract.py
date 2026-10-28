#!/usr/bin/env python3
"""Validate agent-workflow guardrails without third-party Python dependencies."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_FILES = (
    "AGENTS.md",
    "docs/agent-development.md",
    "docs/ci-observability.md",
    ".github/pull_request_template.md",
    ".github/workflows/ci.yml",
    ".github/workflows/dart.yml",
    "tool/ci/check_env_asset_contract.py",
)
REQUIRED_SECTIONS = {
    "AGENTS.md": ("## Repository workflow", "## Commands and evidence", "## Secrets, configuration and external services", "## Completion report"),
    "docs/agent-development.md": ("## 1. Intake and scope", "## 3. Validate and capture evidence", "## 4. Pull Request protocol"),
    "docs/ci-observability.md": ("## Validation layers", "## Interpreting failures", "## Debugging a failure"),
    ".github/pull_request_template.md": ("## Related issue", "## Validation evidence", "## Security and privacy"),
}

def main() -> int:
    errors: list[str] = []
    for relative in REQUIRED_FILES:
        if not (ROOT / relative).is_file():
            errors.append(f"Required agent/CI file is missing: {relative}")

    for relative, sections in REQUIRED_SECTIONS.items():
        path = ROOT / relative
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8")
        for section in sections:
            if section not in content:
                errors.append(f"{relative} is missing required section: {section}")

    ci_path = ROOT / ".github/workflows/ci.yml"
    if ci_path.is_file():
        ci = ci_path.read_text(encoding="utf-8")
        for token in ("pull_request:", "permissions:", "flutter analyze --fatal-infos", "flutter test --coverage", "flutter build apk --release", "upload-artifact@"):
            if token not in ci:
                errors.append(f"CI workflow is missing expected guardrail/check: {token}")
        if "pull_request_target:" in ci:
            errors.append("CI must not use pull_request_target for untrusted code.")
        if "continue-on-error: true" in ci:
            errors.append("Critical quality checks must not be forced green with continue-on-error.")

    release_path = ROOT / ".github/workflows/dart.yml"
    if release_path.is_file():
        release = release_path.read_text(encoding="utf-8")
        for forbidden in ("svenstaro/upload-release-action", "tag: v1.9", "overwrite: true"):
            if forbidden in release:
                errors.append(f"Unsafe legacy release behavior remains in dart.yml: {forbidden}")

    if errors:
        for error in errors:
            print(f"::error::{error}")
        return 1

    print("Agent development contract and workflow guardrails are present.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
