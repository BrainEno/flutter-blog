#!/usr/bin/env python3
"""Check a narrow, documented set of offline documentation invariants."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

from doc_contract.model import Repository
from doc_contract.rules import check
from doc_contract.reporting import report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2],
                        help='repository root (default: location of this script)')
    parser.add_argument('--format', choices=('human', 'json', 'github'), default='human',
                        help='diagnostic output format (default: human)')
    args = parser.parse_args(argv)
    repository = Repository(args.root)
    repository.load()
    errors = check(repository)
    report(errors, len(repository.pages), args.format, sys.stdout, sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
