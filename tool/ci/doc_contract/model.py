"""Repository and document models used by the offline documentation gate."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re

from .markdown import SourceLine, visible_lines
from .reading import read_utf8_bounded


MAX_DOCUMENT_BYTES = 4 * 1024 * 1024


_STATUS = re.compile(r'^>\s*状态：\s*(active|draft|archived)\s*\|\s*分类基线：`([0-9a-f]{7,40})`(?:\s|（|$)')


@dataclass(frozen=True, order=True)
class Diagnostic:
    path: str
    line: int
    rule: str
    message: str

    def render(self) -> str:
        location = f'{self.path}:{self.line}' if self.line else self.path
        return f'{location}: [{self.rule}] {self.message}'


@dataclass(frozen=True)
class Document:
    path: Path
    relative: str
    text: str
    lines: tuple[SourceLine, ...]
    status: str | None
    baseline: str | None
    status_line: int | None

    @classmethod
    def from_path(cls, root: Path, path: Path) -> 'Document':
        text = read_utf8_bounded(path, MAX_DOCUMENT_BYTES)
        relative = path.relative_to(root).as_posix()
        lines = tuple(visible_lines(text))
        headers = [(line.number, match) for line in lines if (match := _STATUS.match(line.text))]
        status = headers[0][1].group(1) if headers else None
        baseline = headers[0][1].group(2) if headers else None
        return cls(path, relative, text, lines, status, baseline, headers[0][0] if headers else None)

    def status_headers(self) -> list[tuple[int, str, str]]:
        return [(line.number, match.group(1), match.group(2))
                for line in self.lines if (match := _STATUS.match(line.text))]

    def malformed_status_headers(self) -> list[int]:
        """Find broken machine-style headers without treating prose as metadata."""
        candidate = re.compile(r'^>\s*状态：\s*[A-Za-z]+\b')
        return [line.number for line in self.lines
                if candidate.match(line.text) and not _STATUS.match(line.text)]


class Repository:
    """Load only repository-owned text; never follow a file outside the root."""

    def __init__(self, root: Path):
        self.root = root.resolve()
        self.errors: list[Diagnostic] = []
        self.documents: dict[str, Document] = {}

    def _load(self, path: Path) -> None:
        relative = path.relative_to(self.root).as_posix()
        try:
            resolved = path.resolve(strict=True)
            if not resolved.is_relative_to(self.root):
                raise ValueError('document resolves outside repository')
            if not resolved.is_file():
                raise ValueError('document is not a regular file')
            if resolved.stat().st_size > MAX_DOCUMENT_BYTES:
                raise ValueError(f'document exceeds {MAX_DOCUMENT_BYTES} bytes')
            self.documents[relative] = Document.from_path(self.root, path)
        except (OSError, UnicodeError, ValueError, RuntimeError) as error:
            self.errors.append(Diagnostic(relative, 0, 'read', str(error)))

    def load(self) -> None:
        readme = self.root / 'README.md'
        index = self.root / 'docs' / 'README.md'
        for required in (readme, index):
            if not required.is_file():
                self.errors.append(Diagnostic(required.relative_to(self.root).as_posix(), 0, 'required', 'required documentation is missing'))
            else:
                self._load(required)
        docs = self.root / 'docs'
        if not docs.is_dir():
            self.errors.append(Diagnostic('docs', 0, 'required', 'documentation directory is missing'))
            return
        for path in sorted(docs.glob('*.md')):
            if path.name != 'README.md':
                self._load(path)

    @property
    def index(self) -> Document | None:
        return self.documents.get('docs/README.md')

    @property
    def pages(self) -> list[Document]:
        return [document for name, document in sorted(self.documents.items())
                if name.startswith('docs/') and name != 'docs/README.md']
