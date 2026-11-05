#!/usr/bin/env python3
"""Audit the assets a built APK ships against the manifest and the sources (#109).

This closes the last acceptance item of the release-engineering issue: prove,
from the artifact rather than from memory, that no known-useless large resource
is bundled. Three questions are answered for every asset inside the APK:

* is it declared in `pubspec.yaml`? (the build and the manifest disagree if not)
* is it referenced at all - from `lib/` sources or from another pubspec section
  such as `fonts:` / `flutter_launcher_icons:`? A file that only exists because
  a directory is declared wholesale is the ~1.1 MiB image this issue opened
  with.
* is it inside the size budget? A near-megabyte asset has to be a decision.

The report also breaks the APK down by bucket and lists the largest entries, so
a size discussion is settled by the artifact instead of by guesswork.
"""
from __future__ import annotations

import argparse
import fnmatch
import pathlib
import sys
import zipfile

#: Where Flutter puts the bundle; a declared `assets/x.png` lands at
#: `assets/flutter_assets/assets/x.png`, i.e. the repository path is kept.
ASSET_PREFIX = 'assets/flutter_assets/'

#: A single bundled asset above this size has to be a deliberate decision.
DEFAULT_BUDGET_BYTES = 1024 * 1024

#: Font license texts must ship (the OFL requires it) but no code references
#: them, so they are declared here instead of being reported as unused.
NON_CODE_ASSETS = ('OFL-*.txt',)


class Analysis:
    def __init__(self, report: str, failures: list[str]):
        self.report = report
        self.failures = failures


def _normalise(value: str) -> str:
    return value.strip().strip('"\'').strip().rstrip('/')


def _manifest_lines(pubspec: str):
    """Yields (indentation level, payload) per pubspec line, comments stripped."""
    for raw in pubspec.splitlines():
        line = raw.split('#', 1)[0].rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        yield len(line) - len(line.lstrip()), stripped


def declared_assets(pubspec: str) -> set[str]:
    """Paths declared under `flutter: assets:` and `fonts:` in a pubspec.

    Directory entries (`- assets/images/`) are kept as bare paths; a bundled
    file counts as declared when it equals an entry or sits below one.
    """
    declared: list[str] = []
    mode = None
    for indentation, stripped in _manifest_lines(pubspec):
        if indentation <= 2:
            mode = None
            if stripped.startswith('assets:'):
                mode = 'assets'
            elif stripped.startswith('fonts:'):
                mode = 'fonts'
            continue
        if mode == 'assets' and stripped.startswith('- '):
            declared.append(stripped[2:])
        elif mode == 'fonts' and stripped.startswith('- asset:'):
            declared.append(stripped[len('- asset:'):])
    return {path for path in (_normalise(entry) for entry in declared) if path}


def manifest_without_asset_list(pubspec: str) -> str:
    """The pubspec text minus the `flutter: assets:` list.

    Removing that list keeps the reference scan honest: an asset must be named
    somewhere other than the declaration that puts it into the bundle.
    """
    kept: list[str] = []
    mode = None
    for raw in pubspec.splitlines():
        payload = raw.split('#', 1)[0]
        stripped = payload.strip()
        indentation = len(payload) - len(payload.lstrip())
        if stripped and indentation <= 2:
            mode = 'assets' if stripped.startswith('assets:') else None
            kept.append(raw)
            continue
        if mode == 'assets':
            continue
        kept.append(raw)
    return '\n'.join(kept)


def source_usage_text(lib_root: pathlib.Path, pubspec: str) -> str:
    """Everything an asset path or basename could legitimately be named in."""
    chunks = [manifest_without_asset_list(pubspec)]
    if lib_root.is_dir():
        for source in sorted(lib_root.rglob('*.dart')):
            chunks.append(source.read_text(encoding='utf-8', errors='replace'))
    return '\n'.join(chunks)


def apk_entries(apk: pathlib.Path) -> list[tuple[str, int]]:
    """Every file in the APK with its uncompressed size."""
    with zipfile.ZipFile(apk) as archive:
        return [
            (info.filename, info.file_size)
            for info in archive.infolist()
            if not info.is_dir()
        ]


def bundled_assets(entries: list[tuple[str, int]]) -> dict[str, int]:
    """The declared-asset subtree of the APK, keyed by repository path.

    `assets/flutter_assets/AssetManifest.bin` and friends are engine files, not
    declared assets, so only paths under `assets/` count.
    """
    return {
        name[len(ASSET_PREFIX):]: size
        for name, size in entries
        if name.startswith(ASSET_PREFIX + 'assets/')
    }


def _is_declared(path: str, declared: set[str]) -> bool:
    return any(path == entry or path.startswith(entry + '/') for entry in declared)


def undeclared_assets(bundled: dict[str, int], declared: set[str]) -> list[str]:
    return sorted(path for path in bundled if not _is_declared(path, declared))


def _is_non_code(path: str) -> bool:
    name = path.rsplit('/', 1)[-1]
    return any(fnmatch.fnmatch(name, pattern) for pattern in NON_CODE_ASSETS)


def unreferenced_assets(bundled: dict[str, int], usage: str) -> list[str]:
    """Assets nothing in `lib/` or the rest of the manifest names."""
    return sorted(
        path
        for path in bundled
        if not _is_non_code(path)
        and path not in usage
        and path.rsplit('/', 1)[-1] not in usage
    )


def oversized_assets(bundled: dict[str, int], budget_bytes: int) -> list[str]:
    return sorted(
        f'{path} ({size} bytes)'
        for path, size in bundled.items()
        if size > budget_bytes
    )


def bucket_of(name: str) -> str:
    """Groups APK entries into the buckets a size discussion actually uses."""
    if name.startswith('lib/'):
        parts = name.split('/')
        return f'lib/{parts[1]}' if len(parts) > 1 else 'lib/'
    if name.startswith(ASSET_PREFIX + 'assets/'):
        return 'assets (declared)'
    if name.startswith('assets/flutter_assets/'):
        return 'assets (engine: manifests, shaders, fonts)'
    if name.startswith('res/'):
        return 'res/'
    if name.startswith('classes') and name.endswith('.dex'):
        return 'dex'
    if name.startswith('META-INF/'):
        return 'META-INF/ (signature)'
    return 'other'


def _human(size: int) -> str:
    if size >= 1024 * 1024:
        return f'{size / (1024 * 1024):.1f} MiB'
    return f'{size / 1024:.0f} KiB'


def size_report(entries: list[tuple[str, int]], top: int = 10) -> str:
    total = sum(size for _, size in entries)
    buckets: dict[str, int] = {}
    for name, size in entries:
        bucket = bucket_of(name)
        buckets[bucket] = buckets.get(bucket, 0) + size
    lines = [f'APK entries: {len(entries)}, total {_human(total)}', '']
    lines.append('By bucket (uncompressed bytes):')
    for bucket, size in sorted(buckets.items(), key=lambda item: -item[1]):
        lines.append(f'  {size:>10}  {_human(size):>9}  {bucket}')
    lines.append('')
    lines.append(f'Largest {top} entries:')
    for name, size in sorted(entries, key=lambda item: -item[1])[:top]:
        lines.append(f'  {size:>10}  {_human(size):>9}  {name}')
    return '\n'.join(lines)


def asset_table(
    bundled: dict[str, int], usage: str, budget_bytes: int
) -> str:
    lines = ['Bundled assets:']
    for path, size in sorted(bundled.items(), key=lambda item: -item[1]):
        flags = []
        if _is_non_code(path):
            flags.append('non-code (license text)')
        elif unreferenced_assets({path: size}, usage):
            flags.append('NOT REFERENCED')
        if size > budget_bytes:
            flags.append('OVER BUDGET')
        suffix = f'  <- {", ".join(flags)}' if flags else ''
        lines.append(f'  {size:>10}  {_human(size):>9}  {path}{suffix}')
    return '\n'.join(lines)


def analyze(
    apk: pathlib.Path,
    pubspec_text: str,
    lib_root: pathlib.Path | None = None,
    budget_bytes: int = DEFAULT_BUDGET_BYTES,
    top: int = 10,
) -> Analysis:
    entries = apk_entries(apk)
    bundled = bundled_assets(entries)
    declared = declared_assets(pubspec_text)
    usage = source_usage_text(lib_root, pubspec_text) if lib_root else None
    failures: list[str] = []
    if not bundled:
        failures.append(
            "no bundled assets found: the APK does not look like this app's "
            'build, so the comparison would pass for the wrong reason'
        )
    undeclared = undeclared_assets(bundled, declared)
    if undeclared:
        failures.append(
            'assets shipped by the APK but not declared in pubspec.yaml: '
            + ', '.join(undeclared)
        )
    if usage is not None:
        unused = unreferenced_assets(bundled, usage)
        if unused:
            failures.append(
                'assets bundled but referenced nowhere in lib/ or the manifest: '
                + ', '.join(unused)
            )
    oversized = oversized_assets(bundled, budget_bytes)
    if oversized:
        failures.append(
            f'assets above the {_human(budget_bytes)} budget: '
            + ', '.join(oversized)
        )
    lines = [size_report(entries, top=top), '']
    if bundled:
        lines.append(asset_table(bundled, usage or '', budget_bytes))
    else:
        lines.append('Bundled assets: none')
    lines.append('')
    lines.append(
        f'Declared assets: {len(declared)} manifest entries, '
        f'{len(bundled)} files bundled, budget {_human(budget_bytes)} per file.'
    )
    if usage is None:
        lines.append('Reference scan skipped: no lib/ directory was given.')
    if failures:
        lines.append('')
        lines.extend(f'FAIL: {failure}' for failure in failures)
    else:
        lines.append(
            'OK: every bundled asset is declared, referenced and inside the '
            'size budget.'
        )
    return Analysis('\n'.join(lines), failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=pathlib.Path)
    parser.add_argument(
        '--pubspec',
        type=pathlib.Path,
        default=pathlib.Path('pubspec.yaml'),
        help='manifest the APK is compared against (default: pubspec.yaml)',
    )
    parser.add_argument(
        '--lib',
        type=pathlib.Path,
        default=pathlib.Path('lib'),
        help='sources scanned for asset references (default: lib)',
    )
    parser.add_argument('--budget-bytes', type=int, default=DEFAULT_BUDGET_BYTES)
    parser.add_argument('--top', type=int, default=10)
    parser.add_argument('--report', type=pathlib.Path)
    args = parser.parse_args()

    if not args.apk.is_file():
        print(f'APK not found: {args.apk}', file=sys.stderr)
        return 1
    if not args.pubspec.is_file():
        print(f'pubspec not found: {args.pubspec}', file=sys.stderr)
        return 1

    analysis = analyze(
        args.apk,
        args.pubspec.read_text(encoding='utf-8'),
        lib_root=args.lib,
        budget_bytes=args.budget_bytes,
        top=args.top,
    )
    print(analysis.report)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(analysis.report + '\n', encoding='utf-8')
    if analysis.failures:
        for failure in analysis.failures:
            print(failure, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
