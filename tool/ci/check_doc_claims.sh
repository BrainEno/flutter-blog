#!/usr/bin/env bash
# Keep the living documentation discoverable and tied to files that exist.
#
# Historical snapshots under docs/archive are indexed and labelled, but are not
# checked for live claims or paths: their value is preserving what was true at
# the time of the review.
#
# Usage: bash tool/ci/check_doc_claims.sh [--root DIRECTORY]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ $# -eq 0 ]]; then
  root="$repo_root"
elif [[ $# -eq 2 && "$1" == "--root" ]]; then
  root="$2"
else
  echo "Usage: $0 [--root DIRECTORY]" >&2
  exit 2
fi

python3 - "$root" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
docs = root / "docs"
index = docs / "README.md"
problems: list[str] = []

if not docs.is_dir():
    problems.append("docs: directory is missing")
if not index.is_file():
    problems.append("docs/README.md: documentation index is missing")
if not (root / "README.md").is_file():
    problems.append("README.md: repository README is missing")

if problems:
    print("\n".join(problems), file=sys.stderr)
    raise SystemExit(1)

archived_root = docs / "archive"
root_docs = sorted(
    path for path in docs.rglob("*.md") if archived_root not in path.parents
)
archived_docs = sorted(archived_root.glob("*.md"))
all_docs = root_docs + archived_docs
status_pattern = re.compile(r"^> 状态：(active|draft|archived)(?:\s|｜|$)", re.MULTILINE)

index_text = index.read_text(encoding="utf-8")
for document in all_docs:
    relative = document.relative_to(docs).as_posix()
    text = document.read_text(encoding="utf-8")
    status = status_pattern.search("\n".join(text.splitlines()[:8]))
    if status is None:
        problems.append(
            f"docs/{relative}: missing status header; use '> 状态：active|draft|archived ｜ …'"
        )
        continue
    if relative.startswith("archive/") and status.group(1) != "archived":
        problems.append(f"docs/{relative}: archived documents must use status 'archived'")
    if not relative.startswith("archive/") and status.group(1) == "archived":
        problems.append(f"docs/{relative}: archived documents must live under docs/archive")
    if relative == "README.md":
        continue
    link = re.compile(r"\]\(" + re.escape(relative) + r"(?:#[^)]+)?\)")
    if link.search(index_text) is None:
        problems.append(f"docs/{relative}: missing from docs/README.md index")

# Living documentation must not make a claim about the current count of open
# issues. That fact changes outside this repository; link to the issue list
# instead. Archived snapshots intentionally retain their historical wording.
live_documents = [root / "README.md"] + root_docs
stale_issue_claim = re.compile(r"只剩\s*#\d+[^\n。]{0,80}开放")
for document in live_documents:
    text = document.read_text(encoding="utf-8")
    if stale_issue_claim.search(text):
        problems.append(
            f"{document.relative_to(root)}: live documentation must not claim which issue is the only open one"
        )

# The app has one runtime article source (no-wave), but it also ships a
# Notion bundle import/export. "There is only one content source" read as "no
# Notion support at all" and hid a finished feature (#287); say which part is
# meant instead. Archived snapshots keep their historical wording.
single_source_claim = re.compile(r"只有一个内容源|内容源只有一个")
for document in live_documents:
    text = document.read_text(encoding="utf-8")
    if single_source_claim.search(text):
        problems.append(
            f"{document.relative_to(root)}: live documentation must not claim a single content "
            "source without scope; distinguish the runtime source from the Notion bundle "
            "import/export"
        )

# Only backticked repository paths are checked. URLs and prose that happen to
# contain a slash are deliberately outside this small contract. A glob or an
# angle-bracket placeholder is documentation notation rather than one concrete
# path and is therefore skipped.
path_pattern = re.compile(r"`((?:lib|docs)/[^`\n]+)`")
line_suffix = re.compile(r":\d+(?:-L?\d+)?$")
for document in live_documents:
    for line_number, line in enumerate(document.read_text(encoding="utf-8").splitlines(), 1):
        for raw_path in path_pattern.findall(line):
            path = raw_path.split("#", 1)[0].rstrip(".,;:")
            path = line_suffix.sub("", path)
            if any(marker in path for marker in ("*", "<", ">", "…")):
                continue
            if not (root / path).exists():
                relative = document.relative_to(root).as_posix()
                problems.append(f"{relative}:{line_number}: referenced path does not exist: {raw_path}")

if problems:
    print("\n".join(problems), file=sys.stderr)
    print(f"{len(problems)} documentation claim violation(s).", file=sys.stderr)
    raise SystemExit(1)

print("Documentation index, status headers, live claims, and referenced paths are valid.")
PY
