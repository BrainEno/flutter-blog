"""Bounded UTF-8 reads for checked-in text used by the documentation gate."""
from __future__ import annotations

from pathlib import Path


def read_utf8_bounded(path: Path, limit: int) -> str:
    """Read at most limit+1 bytes, failing instead of allocating an unbounded file.

    The caller is responsible for checking repository containment and file type.
    Checking the bytes read (not just stat) also covers files growing after stat.
    """
    if limit <= 0:
        raise ValueError('text read limit must be positive')
    with path.open('rb') as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f'file exceeds {limit} bytes')
    return data.decode('utf-8', errors='strict')
