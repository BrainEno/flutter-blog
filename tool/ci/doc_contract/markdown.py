"""Small, bounded Markdown scanner for repository-document contracts.

This is not a CommonMark renderer. It extracts the narrow syntactic forms used
by the contract while preserving line numbers. Code fences and HTML comments
are ignored; malformed syntax never causes external network access.
"""
from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Iterator


@dataclass(frozen=True)
class SourceLine:
    number: int
    text: str


@dataclass(frozen=True)
class InlineCode:
    line: int
    value: str


@dataclass(frozen=True)
class Link:
    line: int
    label: str
    destination: str
    image: bool = False
    start: int = 0
    end: int = 0


_FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')
_REFERENCE = re.compile(r'^ {0,3}\[([^\]\n]+)\]:\s*(.*)$')


def visible_lines(text: str) -> Iterator[SourceLine]:
    """Yield lines outside fences and comments, retaining their source lines.

    Fence closures must use the same character and at least the opening run's
    length. Comments may start or end mid-line and may cover several lines.
    Indented code is not interpreted as prose. It is intentionally ignored rather
    than guessing whether example paths are references to the current tree.
    """
    fence_char: str | None = None
    fence_length = 0
    comment = False
    for number, original in enumerate(text.splitlines(), 1):
        if fence_char is not None:
            stripped = original.lstrip(' ')
            indent = len(original) - len(stripped)
            if indent <= 3:
                run = len(stripped) - len(stripped.lstrip(fence_char))
                if run >= fence_length and not stripped[run:].strip():
                    fence_char = None
            continue
        pieces: list[str] = []
        pos = 0
        while pos < len(original):
            if comment:
                end = original.find('-->', pos)
                if end < 0:
                    pos = len(original)
                else:
                    pieces.append(' ')
                    pos = end + 3
                    comment = False
            else:
                start = original.find('<!--', pos)
                if start < 0:
                    pieces.append(original[pos:])
                    break
                pieces.append(original[pos:start])
                pos = start + 4
                comment = True
        line = ''.join(pieces)
        match = _FENCE.match(line)
        if match:
            marker, suffix = match.groups()
            if marker[0] != '`' or '`' not in suffix:
                fence_char = marker[0]
                fence_length = len(marker)
                continue
        if line.startswith(('    ', '\t')):
            continue
        yield SourceLine(number, line)


def _escaped(text: str, index: int) -> bool:
    slash_count = 0
    index -= 1
    while index >= 0 and text[index] == '\\':
        slash_count += 1
        index -= 1
    return slash_count % 2 == 1


def _run(text: str, start: int, char: str) -> int:
    end = start
    while end < len(text) and text[end] == char:
        end += 1
    return end - start


def _code_end(text: str, start: int, count: int) -> int | None:
    index = start + count
    while index < len(text):
        if text[index] != '`':
            index += 1
            continue
        length = _run(text, index, '`')
        if length == count:
            return index
        index += length
    return None


def inline_codes(line: SourceLine) -> Iterator[InlineCode]:
    """Extract matched backtick spans, including multi-backtick delimiters."""
    index = 0
    while index < len(line.text):
        if line.text[index] != '`' or _escaped(line.text, index):
            index += 1
            continue
        count = _run(line.text, index, '`')
        end = _code_end(line.text, index, count)
        if end is None:
            index += count
            continue
        value = line.text[index + count:end].replace('\n', ' ')
        if value.startswith(' ') and value.endswith(' ') and value.strip():
            value = value[1:-1]
        yield InlineCode(line.number, value)
        index = end + count


def _closing_bracket(text: str, start: int) -> int | None:
    depth = 1
    index = start + 1
    while index < len(text):
        char = text[index]
        if _escaped(text, index):
            index += 1
            continue
        if char == '`':
            count = _run(text, index, '`')
            end = _code_end(text, index, count)
            if end is not None:
                index = end + count
                continue
        if char == '[':
            depth += 1
        elif char == ']':
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def _parenthesized(text: str, start: int) -> tuple[str, int] | None:
    """Read a destination, respecting nested parentheses and escaped chars."""
    index = start + 1
    while index < len(text) and text[index] in ' \t':
        index += 1
    if index >= len(text):
        return None
    if text[index] == '<':
        end = index + 1
        while end < len(text) and (text[end] != '>' or _escaped(text, end)):
            end += 1
        if end >= len(text):
            return None
        destination = text[index + 1:end]
        index = end + 1
    else:
        begin = index
        depth = 0
        while index < len(text):
            char = text[index]
            if _escaped(text, index):
                index += 1
            elif char == '(':
                depth += 1
            elif char == ')':
                if depth == 0:
                    break
                depth -= 1
            elif char.isspace() and depth == 0:
                break
            index += 1
        destination = text[begin:index]
    # Optional title is intentionally ignored but must end inside this link.
    quote: str | None = None
    while index < len(text):
        char = text[index]
        if quote:
            if char == quote and not _escaped(text, index):
                quote = None
        elif char in "\"'":
            quote = char
        elif char == ')':
            return destination, index + 1
        elif not char.isspace():
            return None
        index += 1
    return None


def _normal_label(label: str) -> str:
    return ' '.join(label.split()).casefold()


def _reference_destination(text: str) -> str | None:
    text = text.strip()
    if not text:
        return None
    if text.startswith('<'):
        end = text.find('>')
        return text[1:end] if end > 0 else None
    return text.split(None, 1)[0]


def links(lines: list[SourceLine]) -> Iterator[Link]:
    """Extract inline and reference links on a single line.

    Reference definitions may follow their uses. Nested labels and parentheses
    in destinations are accepted. Images are identified separately so an image
    cannot satisfy a document-index entry.
    """
    definitions: dict[str, str] = {}
    for line in lines:
        match = _REFERENCE.match(line.text)
        if match:
            destination = _reference_destination(match.group(2))
            if destination is not None:
                definitions.setdefault(_normal_label(match.group(1)), destination)
    for line in lines:
        text = line.text
        if _REFERENCE.match(text):
            continue
        index = 0
        while index < len(text):
            if text[index] == '`' and not _escaped(text, index):
                count = _run(text, index, '`')
                end = _code_end(text, index, count)
                index = end + count if end is not None else index + count
                continue
            if text[index] != '[' or _escaped(text, index):
                index += 1
                continue
            end = _closing_bracket(text, index)
            if end is None:
                index += 1
                continue
            label = text[index + 1:end]
            after = end + 1
            destination: str | None = None
            consumed = after
            if after < len(text) and text[after] == '(':
                parsed = _parenthesized(text, after)
                if parsed is not None:
                    destination, consumed = parsed
            elif after < len(text) and text[after] == '[':
                ref_end = _closing_bracket(text, after)
                if ref_end is not None:
                    ref = text[after + 1:ref_end] or label
                    destination = definitions.get(_normal_label(ref))
                    consumed = ref_end + 1
            else:
                destination = definitions.get(_normal_label(label))
            if destination is not None:
                image = index > 0 and text[index - 1] == '!' and not _escaped(text, index - 1)
                yield Link(line.number, label, destination, image, index, consumed)
            index = max(consumed, end + 1)


def _heading_text(value: str) -> str:
    """Remove Markdown markup from the simple heading forms used in docs.

    Link text contributes to a GitHub heading anchor; its destination does not.
    Inline code contributes its content. This is deliberately not a renderer and
    cannot resolve raw HTML or dynamically generated custom anchor attributes.
    """
    line = SourceLine(1, value)
    spans = list(links([line]))
    if spans:
        # Replace full inline links before removing punctuation. Reference-style
        # headings need no special handling in the current document convention.
        value = re.sub(r'!?\[([^\]]+)\]\([^)]*\)', r'\1', value)
    value = re.sub(r'<[^>]+>', '', value)
    value = value.replace('`', '').replace('*', '').replace('__', '')
    value = re.sub(r'\\([!"#$%&\'()*+,\-./:;<=>?@\[\\\]^_`{|}~])', r'\1', value)
    return value.strip()


def heading_anchors(lines: list[SourceLine]) -> set[str]:
    """Collect GitHub-style heading IDs, including duplicate suffixes.

    Only ATX and setext Markdown headings are accepted. Custom HTML anchors,
    generated headings and full Markdown rendering are outside this contract.
    """
    import unicodedata

    anchors: set[str] = set()
    counts: dict[str, int] = {}

    def add(title: str) -> None:
        text = _heading_text(title).lower()
        slug = ''.join(char for char in text
                       if char in '-_ ' or unicodedata.category(char)[0] in ('L', 'N', 'M'))
        slug = slug.replace(' ', '-')
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(slug if count == 0 else f'{slug}-{count}')

    previous: SourceLine | None = None
    for line in lines:
        match = re.match(r'^ {0,3}#{1,6}(?:\s+|$)(.*)$', line.text)
        if match:
            title = re.sub(r'\s+#+\s*$', '', match.group(1))
            add(title)
        elif (previous is not None and line.number == previous.number + 1 and
              previous.text.strip() and re.match(r'^ {0,3}(?:=+|-+)\s*$', line.text)):
            add(previous.text.strip())
        previous = line
    return anchors
