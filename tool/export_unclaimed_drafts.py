#!/usr/bin/env python3
"""Export ownerless legacy SQLite drafts without assigning them to an account.

Run against a trusted, stopped-app SQLite copy. It only reads SQLite: the
retired Isar files cannot be read any more (#107), and it does not install or
import the resulting JSON. The exported file contains private article text. See
docs/unclaimed-drafts.md before handling it.
"""

import argparse
import base64
import json
import os
from pathlib import Path
import sqlite3
import stat
import sys
from typing import Any


_COLUMNS = ("id", "blog_id", "title", "content", "tags", "updated_at")


def _json_value(value: Any) -> Any:
    # Normally text fields are strings. SQLite can also contain BLOBs; preserve
    # their exact bytes rather than decoding or silently replacing them.
    if isinstance(value, bytes):
        return {"encoding": "base64", "data": base64.b64encode(value).decode("ascii")}
    return value


def export(source: Path, destination: Path) -> int:
    if os.name != "posix":
        raise RuntimeError("This tool requires POSIX file permissions; use Linux, macOS or WSL.")

    # mode=ro prevents SQL writes. Do not use immutable=1: it would ignore an
    # existing WAL and could produce an incomplete export. The app must be
    # stopped and all SQLite sidecars copied consistently as documented.
    uri = source.resolve(strict=True).as_uri() + "?mode=ro"
    db = sqlite3.connect(uri, uri=True)
    try:
        db.execute("PRAGMA query_only = ON")
        cursor = db.execute(
            "SELECT id, blog_id, title, content, tags, updated_at FROM drafts ORDER BY id"
        )
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(destination, flags, 0o600)
        identity = os.fstat(fd)
        count = 0
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as out:
                out.write('{"format":"belog-unclaimed-drafts-v1","drafts":[')
                for row in cursor:
                    if count:
                        out.write(",")
                    record = dict(zip(_COLUMNS, map(_json_value, row)))
                    json.dump(record, out, ensure_ascii=True, allow_nan=False)
                    count += 1
                out.write("]}\n")
                out.flush()
                os.fsync(out.fileno())
        except BaseException:
            # Only remove the partial file if it is still the one we created.
            try:
                current = os.stat(destination, follow_symlinks=False)
                if stat.S_ISREG(current.st_mode) and os.path.samestat(identity, current):
                    os.unlink(destination)
            except OSError:
                pass
            raise
        return count
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="trusted SQLite database copy")
    parser.add_argument("destination", type=Path, help="new JSON file; must not exist")
    args = parser.parse_args()
    try:
        count = export(args.source, args.destination)
    except (OSError, ValueError, TypeError, sqlite3.Error, RuntimeError):
        # Do not print article fields or raw database errors to a terminal or CI.
        print(
            "Export failed. Check the source is a readable trusted SQLite copy "
            "with a legacy drafts table and the destination does not exist.",
            file=sys.stderr,
        )
        return 1
    print(f"Exported {count} unclaimed legacy draft(s); ownership is not verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
