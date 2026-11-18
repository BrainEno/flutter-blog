"""Bounded local path-pattern matching for untrusted Markdown references.

Patterns are repository-relative and do not follow symlinked directories. A
budget exhaustion or unreadable directory is an error, not a vacuous pass.
This is intentionally narrower than Python glob: it prevents recursive
symlink loops and never scans outside the repository.
"""
from __future__ import annotations

from dataclasses import dataclass
import fnmatch
import os
from pathlib import Path


MAX_PATTERN_LENGTH = 1024
MAX_PATTERN_SEGMENTS = 64
MAX_SCAN_ENTRIES = 100_000
MAX_RECURSIVE_DEPTH = 32


class PatternError(ValueError):
    pass


@dataclass
class _Budget:
    remaining: int = MAX_SCAN_ENTRIES

    def take(self) -> None:
        self.remaining -= 1
        if self.remaining < 0:
            raise PatternError('path pattern exceeded the scan budget')


def _segments(pattern: str) -> tuple[str, ...]:
    if not pattern or len(pattern) > MAX_PATTERN_LENGTH:
        raise PatternError('invalid path pattern length')
    if any(ord(char) < 32 or ord(char) == 127 for char in pattern):
        raise PatternError('path pattern contains control characters')
    if pattern.startswith('/') or '\\' in pattern:
        raise PatternError('path pattern must be repository-relative')
    parts = tuple(pattern.split('/'))
    if len(parts) > MAX_PATTERN_SEGMENTS:
        raise PatternError('path pattern has too many segments')
    if any(part in ('.', '..') for part in parts):
        raise PatternError('path pattern may not traverse directories')
    if any(not part for part in parts[:-1]):
        raise PatternError('path pattern has an empty segment')
    return parts[:-1] if parts[-1] == '' else parts


def _inside(root: Path, path: Path) -> bool:
    try:
        return path.resolve().is_relative_to(root)
    except (OSError, RuntimeError) as error:
        raise PatternError(f'cannot resolve path safely: {error}') from error


def _children(directory: Path, budget: _Budget):
    try:
        with os.scandir(directory) as iterator:
            entries = []
            for entry in iterator:
                budget.take()
                entries.append(entry)
            # Keep diagnostics and traversal stable across platforms.
            return sorted(entries, key=lambda entry: entry.name)
    except OSError as error:
        raise PatternError(f'cannot inspect directory: {error.strerror or error}') from error


def _ordinary_dir(entry: os.DirEntry[str]) -> bool:
    try:
        return entry.is_dir(follow_symlinks=False)
    except OSError as error:
        raise PatternError(f'cannot inspect path: {error.strerror or error}') from error


def _matches(root: Path, directory: Path, parts: tuple[str, ...],
             index: int, depth: int, budget: _Budget) -> bool:
    if index == len(parts):
        return directory.exists() and _inside(root, directory)
    part = parts[index]
    if part == '**':
        if _matches(root, directory, parts, index + 1, depth, budget):
            return True
        if depth >= MAX_RECURSIVE_DEPTH:
            raise PatternError('path pattern exceeded recursive depth')
        for entry in _children(directory, budget):
            if _ordinary_dir(entry) and _matches(root, Path(entry.path), parts, index, depth + 1, budget):
                return True
        return False
    wildcard = any(char in part for char in '*?[')
    if wildcard:
        for entry in _children(directory, budget):
            if not fnmatch.fnmatchcase(entry.name, part):
                continue
            path = Path(entry.path)
            if index == len(parts) - 1:
                if path.exists() and _inside(root, path):
                    return True
            elif _ordinary_dir(entry) and _matches(root, path, parts, index + 1, depth, budget):
                return True
        return False
    path = directory / part
    if not _inside(root, path):
        raise PatternError('path resolves outside the repository')
    if index == len(parts) - 1:
        return path.exists()
    # A symlinked directory is not traversed, even when it points inside root.
    if path.is_symlink() or not path.is_dir():
        return False
    return _matches(root, path, parts, index + 1, depth, budget)


def path_exists(root: Path, pattern: str) -> bool:
    """Return whether a safe path or segment-glob resolves inside root.

    `**` matches zero or more directory levels. Other glob characters only
    match within one segment; no brace expansion or shell interpretation occurs.
    A dangling symlink is not a match. The caller supplies an existing root.
    """
    root = root.resolve(strict=True)
    parts = _segments(pattern)
    if not parts:
        return False
    return _matches(root, root, parts, 0, 0, _Budget())
