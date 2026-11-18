"""Human, JSON and GitHub Actions diagnostics for the documentation gate."""
from __future__ import annotations

from dataclasses import asdict
import json
from typing import TextIO

from .model import Diagnostic


def _escape_bounded(value: str, limit: int, *, property_value: bool = False) -> str:
    """Encode Actions command delimiters while respecting the output budget.

    Bound the escaped form, not the input: a single percent sign can become
    three characters. Never cut an escape sequence or introduce a raw newline.
    """
    encoded: list[str] = []
    used = 0
    replacements = {'%': '%25', '\r': '%0D', '\n': '%0A'}
    if property_value:
        replacements.update({':': '%3A', ',': '%2C'})
    for character in value:
        piece = replacements.get(character, character)
        if used + len(piece) > limit:
            break
        encoded.append(piece)
        used += len(piece)
    if len(encoded) < len(value) and used + 3 <= limit:
        encoded.append('...')
    return ''.join(encoded)


def github_annotation(error: Diagnostic) -> str:
    path = _escape_bounded(error.path, 500, property_value=True)
    properties = [f'file={path}']
    if error.line > 0:
        properties.append(f'line={error.line}')
    title = _escape_bounded('Document contract: ' + error.rule, 120, property_value=True)
    properties.append(f'title={title}')
    message = _escape_bounded(error.message, 3000)
    return f'::error {",".join(properties)}::{message}'


def report(errors: list[Diagnostic], pages: int, style: str,
           stdout: TextIO, stderr: TextIO) -> None:
    """Render diagnostics without changing their order or hiding failures."""
    if style == 'json':
        payload = {'ok': not errors, 'documents': pages,
                   'diagnostics': [asdict(error) for error in errors]}
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True), file=stdout)
        return
    if not errors:
        print(f'Documentation contract passed: {pages} indexed documents.', file=stdout)
        return
    for error in errors:
        print(github_annotation(error) if style == 'github' else error.render(),
              file=stdout if style == 'github' else stderr)
    print(f'Documentation contract failed: {len(errors)} problem(s).', file=stderr)
