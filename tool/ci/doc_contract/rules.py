"""Deterministic, offline checks for indexed documentation and claims.

These checks identify a few mechanically verifiable classes of drift. They do
not prove that natural-language statements, historical baselines, remote URLs,
security guarantees, backend deployments or product decisions are correct.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

from .markdown import InlineCode, inline_codes, links
from .model import Diagnostic, Document, Repository
from .paths import PatternError, path_exists


# Dates are scoped to the paragraph containing the historical claim; a date in
# a distant title must not silently excuse a current-looking statement.
_DATE = re.compile(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)')
_ISSUE = re.compile(r'#\s*\d+')
_CHINESE_REMAINING = re.compile(r'(?:只剩|仅剩|唯一开放|唯一未关闭).{0,65}(?:开放|未关闭|issue|问题)', re.I)
_ENGLISH_REMAINING = re.compile(r'(?:only|sole|last|remaining).{0,60}(?:open|unclosed).{0,30}(?:issue|#\s*\d+)|(?:only|sole|last).{0,40}issue.{0,40}(?:open|remaining)', re.I)
_ROOT_REFERENCE = re.compile(r'^(?:lib|docs)/')
_CONTROL = re.compile(r'[\x00-\x1f\x7f]')


def _valid_date(text: str) -> bool:
    for year, month, day in _DATE.findall(text):
        try:
            date(int(year), int(month), int(day))
            return True
        except ValueError:
            pass
    return False


def _paragraphs(document: Document):
    """Return prose paragraphs with the first source line retained."""
    first = 0
    parts: list[str] = []
    previous = 0
    for line in document.lines:
        # A blank line or a fence/comment gap ends the paragraph. Table rows and
        # list items are independent statements, even without blank lines.
        boundary = (not line.text.strip() or line.number != previous + 1 or
                    bool(re.match(r'^\s*(?:[-*+]\s|\d+[.)]\s|\|)', line.text)))
        if boundary and parts:
            yield first, ' '.join(parts)
            parts = []
        if line.text.strip():
            if not parts:
                first = line.number
            parts.append(line.text.strip())
        previous = line.number
    if parts:
        yield first, ' '.join(parts)


def _clean_prose(value: str) -> str:
    # Strip emphasis syntax without removing the issue ID or the date.
    return value.replace('**', '').replace('__', '').replace('`', '')


def check_status(repository: Repository) -> list[Diagnostic]:
    errors: list[Diagnostic] = []
    for doc in repository.pages:
        headers = doc.status_headers()
        for line in doc.malformed_status_headers():
            errors.append(Diagnostic(doc.relative, line, 'status', 'malformed status metadata; use an allowed status and commit baseline'))
        if len(headers) != 1:
            errors.append(Diagnostic(doc.relative, 0, 'status', 'expected exactly one status header: > 状态：active|draft|archived | 分类基线：`<commit>`'))
            continue
        line, _, _ = headers[0]
        if line > 6:
            errors.append(Diagnostic(doc.relative, line, 'status', 'status header must appear near the document title'))
    return errors


def check_issue_claims(repository: Repository) -> list[Diagnostic]:
    errors: list[Diagnostic] = []
    for doc in repository.documents.values():
        for line, paragraph in _paragraphs(doc):
            text = _clean_prose(paragraph)
            if not _ISSUE.search(text):
                continue
            if not (_CHINESE_REMAINING.search(text) or _ENGLISH_REMAINING.search(text)):
                continue
            if doc.status == 'archived' and _valid_date(text):
                continue
            errors.append(Diagnostic(doc.relative, line, 'live-issues', 'do not assert a live remaining issue count; link to the issue list. Only dated archived snapshots may retain historical claims'))
    return errors


def _local_target(root: Path, doc: Document, destination: str) -> tuple[Path | None, str | None]:
    """Resolve a local Markdown destination without following outside-root paths."""
    try:
        parsed = urlsplit(destination)
    except ValueError:
        return None, 'invalid link destination'
    if parsed.scheme or parsed.netloc or destination.startswith('//'):
        return None, None
    path = unquote(parsed.path)
    if not path:
        return None, None
    if _CONTROL.search(path) or '\\' in path:
        return None, 'invalid local link path'
    target = (root / path.lstrip('/')) if path.startswith('/') else (doc.path.parent / path)
    try:
        resolved = target.resolve()
    except (OSError, RuntimeError):
        return None, 'local link cannot be resolved safely'
    if not resolved.is_relative_to(root):
        return None, 'local link escapes repository'
    return resolved, None


def check_index(repository: Repository) -> list[Diagnostic]:
    index = repository.index
    if index is None:
        return []
    errors: list[Diagnostic] = []
    occurrences: dict[str, list[int]] = defaultdict(list)
    for link in links(list(index.lines)):
        if link.image:
            continue
        target, problem = _local_target(repository.root, index, link.destination)
        if problem:
            errors.append(Diagnostic(index.relative, link.line, 'index-link', problem))
            continue
        if target is None or target.parent != (repository.root / 'docs').resolve() or target.suffix.lower() != '.md':
            continue
        relative = target.relative_to(repository.root).as_posix()
        if relative == 'docs/README.md':
            continue
        if not link.label.strip():
            errors.append(Diagnostic(index.relative, link.line, 'index-link',
                                     f'{relative} needs a readable index label'))
        occurrences[relative].append(link.line)
        target_doc = repository.documents.get(relative)
        if target_doc is None:
            errors.append(Diagnostic(index.relative, link.line, 'index-link', f'indexed document does not exist: {relative}'))
        elif target_doc.status is not None:
            source_line = next((item.text for item in index.lines if item.number == link.line), '')
            suffix = source_line[link.end:]
            marker = re.match(r'^\s*[（(](active|draft|archived)[）)]', suffix)
            if marker is not None and marker.group(1) != target_doc.status:
                errors.append(Diagnostic(index.relative, link.line, 'index-status',
                                         f'{relative} has index status {marker.group(1)}, but its header is {target_doc.status}'))
            elif marker is None and target_doc.status in ('draft', 'archived'):
                errors.append(Diagnostic(index.relative, link.line, 'index-status',
                                         f'{relative} must be marked （{target_doc.status}） immediately after its link'))
    for doc in repository.pages:
        found = occurrences.get(doc.relative, [])
        if not found:
            errors.append(Diagnostic(index.relative, 0, 'index-missing', f'{doc.relative} is not linked in the index'))
        elif len(found) > 1:
            errors.append(Diagnostic(index.relative, found[1], 'index-duplicate', f'{doc.relative} is linked more than once (first at line {found[0]})'))
    return errors


def _reference_path(code: InlineCode) -> str | None:
    value = code.value.strip()
    if not _ROOT_REFERENCE.match(value):
        return None
    # A code sample, expression, or a platform binary path isn't a literal
    # repository path. Explicit placeholders such as <abi> are examples.
    if any(char.isspace() for char in value) or any(char in value for char in '<>{}'):
        return None
    if '?' in value:
        return None
    value = value.split('#', 1)[0]
    value = re.sub(r':\d+(?::\d+)?$', '', value)
    return value if value else None


def _path_problem(root: Path, value: str) -> str | None:
    if _CONTROL.search(value) or '\\' in value:
        return 'invalid path characters'
    try:
        if not path_exists(root, value):
            return 'path or pattern does not exist'
    except PatternError as error:
        return str(error)
    return None


def check_references(repository: Repository) -> list[Diagnostic]:
    errors: list[Diagnostic] = []
    for doc in repository.documents.values():
        for line in doc.lines:
            for code in inline_codes(line):
                path = _reference_path(code)
                if path is None:
                    continue
                problem = _path_problem(repository.root, path)
                if problem:
                    errors.append(Diagnostic(doc.relative, code.line, 'path', f'{problem}: {path}'))
    return errors


def check(repository: Repository) -> list[Diagnostic]:
    """Run every independent rule and report all violations in stable order."""
    from .evidence import check_evidence

    return sorted(repository.errors + check_status(repository) + check_index(repository) +
                  check_issue_claims(repository) + check_references(repository) +
                  check_local_links(repository) + check_evidence(repository))


def check_local_links(repository: Repository) -> list[Diagnostic]:
    """Check local Markdown link targets; do not fetch or validate remote URLs.

    Anchors are checked for Markdown pages loaded into the repository model;
    other file fragments may be source line references and are left alone.
    """
    from .markdown import heading_anchors

    errors: list[Diagnostic] = []
    cache: dict[str, set[str]] = {}
    for doc in repository.documents.values():
        for link in links(list(doc.lines)):
            target, problem = _local_target(repository.root, doc, link.destination)
            if problem:
                errors.append(Diagnostic(doc.relative, link.line, 'link', problem))
                continue
            try:
                parsed = urlsplit(link.destination)
            except ValueError:
                continue
            if parsed.scheme or parsed.netloc or link.destination.startswith('//'):
                continue
            if target is None and parsed.fragment:
                target = doc.path.resolve()
            if target is None:
                continue
            if not target.exists():
                errors.append(Diagnostic(doc.relative, link.line, 'link', f'local target does not exist: {link.destination}'))
                continue
            if not parsed.fragment:
                continue
            name = target.relative_to(repository.root).as_posix()
            target_doc = repository.documents.get(name)
            if target_doc is None:
                continue
            if name not in cache:
                cache[name] = heading_anchors(list(target_doc.lines))
            fragment = unquote(parsed.fragment)
            if fragment not in cache[name]:
                errors.append(Diagnostic(doc.relative, link.line, 'anchor', f'heading anchor not found: {link.destination}'))
    return errors
