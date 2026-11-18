"""Explicit, reviewable literal evidence for a small set of volatile claims.

The manifest is not a proof of behavior. It couples named prose to small source
markers so a source edit prompts a human to re-check the related documentation.
The input is data only: no expression evaluation, network access or shell calls.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path, PurePosixPath
import re
from typing import Any

from .model import Diagnostic, Repository
from .reading import read_utf8_bounded


_MANIFEST = 'tool/ci/doc-claim-evidence.json'
_MAX_MANIFEST_BYTES = 256 * 1024
_MAX_FILE_BYTES = 4 * 1024 * 1024
_MAX_CLAIMS = 100
_MAX_MARKERS = 40
_ID = re.compile(r'^[a-z][a-z0-9-]{2,79}$')


@dataclass(frozen=True)
class EvidenceFile:
    path: str
    contains: tuple[str, ...]
    absent: tuple[str, ...]


@dataclass(frozen=True)
class Claim:
    id: str
    description: str
    documents: tuple[EvidenceFile, ...]
    sources: tuple[EvidenceFile, ...]


class ManifestError(ValueError):
    pass


def _object(value: Any, fields: set[str], location: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != fields:
        raise ManifestError(f'{location} must contain exactly {", ".join(sorted(fields))}')
    return value


def _string(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 4000:
        raise ManifestError(f'{location} must be a nonempty string of at most 4000 characters')
    if '\x00' in value:
        raise ManifestError(f'{location} contains a NUL character')
    return value


def _markers(value: Any, location: str) -> tuple[str, ...]:
    if not isinstance(value, list) or len(value) > _MAX_MARKERS:
        raise ManifestError(f'{location} must be an array of at most {_MAX_MARKERS} literals')
    markers = tuple(_string(item, location) for item in value)
    if len(set(markers)) != len(markers):
        raise ManifestError(f'{location} has duplicate literals')
    return markers


def _file(value: Any, location: str, *, document: bool) -> EvidenceFile:
    obj = _object(value, {'path', 'contains', 'absent'}, location)
    name = _string(obj['path'], f'{location}.path')
    path = PurePosixPath(name)
    if (name != path.as_posix() or path.is_absolute() or
            any(part in ('.', '..') for part in path.parts) or '\\' in name):
        raise ManifestError(f'{location}.path must be a normalized repository-relative path')
    if document and not (name == 'README.md' or (name.startswith('docs/') and name.endswith('.md'))):
        raise ManifestError(f'{location}.path must name a documentation file')
    if not document and not name.startswith('lib/'):
        raise ManifestError(f'{location}.path must name a source file under lib/')
    present = _markers(obj['contains'], f'{location}.contains')
    absent = _markers(obj['absent'], f'{location}.absent')
    if not present and not absent:
        raise ManifestError(f'{location} must check at least one literal')
    if set(present) & set(absent):
        raise ManifestError(f'{location} both requires and forbids the same literal')
    return EvidenceFile(name, present, absent)


def parse_manifest(text: str) -> tuple[Claim, ...]:
    try:
        data = json.loads(text, object_pairs_hook=_unique_object)
    except (ValueError, TypeError) as error:
        raise ManifestError(f'invalid JSON: {error}') from error
    obj = _object(data, {'version', 'claims'}, 'manifest')
    if type(obj['version']) is not int or obj['version'] != 1:
        raise ManifestError('manifest version must be 1')
    raw = obj['claims']
    if not isinstance(raw, list) or not raw or len(raw) > _MAX_CLAIMS:
        raise ManifestError(f'claims must be a nonempty array of at most {_MAX_CLAIMS} entries')
    claims: list[Claim] = []
    ids: set[str] = set()
    for index, value in enumerate(raw):
        location = f'claims[{index}]'
        item = _object(value, {'id', 'description', 'documents', 'sources'}, location)
        name = _string(item['id'], f'{location}.id')
        if not _ID.fullmatch(name) or name in ids:
            raise ManifestError(f'{location}.id must be unique lowercase kebab-case')
        ids.add(name)
        description = _string(item['description'], f'{location}.description')
        groups: list[tuple[EvidenceFile, ...]] = []
        for group in ('documents', 'sources'):
            entries = item[group]
            if not isinstance(entries, list) or not entries or len(entries) > _MAX_MARKERS:
                raise ManifestError(f'{location}.{group} must be a nonempty bounded array')
            files = tuple(_file(entry, f'{location}.{group}[{i}]', document=group == 'documents')
                          for i, entry in enumerate(entries))
            if len({file.path for file in files}) != len(files):
                raise ManifestError(f'{location}.{group} repeats a file')
            groups.append(files)
        claims.append(Claim(name, description, groups[0], groups[1]))
    return tuple(claims)


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ManifestError(f'duplicate key {key!r}')
        result[key] = value
    return result


def _read(root: Path, name: str, limit: int) -> str:
    target = (root / name).resolve(strict=True)
    if not target.is_relative_to(root) or not target.is_file():
        raise ValueError('file must resolve inside the repository')
    if target.stat().st_size > limit:
        raise ValueError(f'file exceeds {limit} bytes')
    return read_utf8_bounded(target, limit)


def _describe_marker(marker: str) -> str:
    """Display only a bounded, escaped literal from the committed manifest."""
    visible = repr(marker)
    if len(visible) > 120:
        return visible[:117] + '...'
    return visible


def _line_of(text: str, marker: str) -> int:
    position = text.find(marker)
    return 0 if position < 0 else text.count('\n', 0, position) + 1


def check_evidence(repository: Repository) -> list[Diagnostic]:
    errors: list[Diagnostic] = []
    try:
        claims = parse_manifest(_read(repository.root, _MANIFEST, _MAX_MANIFEST_BYTES))
    except (OSError, UnicodeError, ValueError, RuntimeError) as error:
        return [Diagnostic(_MANIFEST, 0, 'evidence-manifest', str(error))]
    cache: dict[str, str] = {}
    for claim in claims:
        for file in (*claim.documents, *claim.sources):
            try:
                if file.path not in cache:
                    cache[file.path] = _read(repository.root, file.path, _MAX_FILE_BYTES)
                text = cache[file.path]
            except (OSError, UnicodeError, ValueError, RuntimeError) as error:
                errors.append(Diagnostic(file.path, 0, 'evidence-read', f'{claim.id}: {error}'))
                continue
            for marker in file.contains:
                if marker not in text:
                    errors.append(Diagnostic(file.path, 0, 'evidence', f'{claim.id}: required literal {_describe_marker(marker)} missing; review {claim.description!r} and its manifest'))
            for marker in file.absent:
                if marker in text:
                    errors.append(Diagnostic(file.path, _line_of(text, marker), 'evidence', f'{claim.id}: forbidden literal {_describe_marker(marker)} found; review {claim.description!r} and its manifest'))
    return errors
