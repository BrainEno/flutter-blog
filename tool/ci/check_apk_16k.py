#!/usr/bin/env python3
"""Check every APK native ELF LOAD segment with Android NDK llvm-readelf.

Pair this with `zipalign -c -P 16 -v 4 APK` to check ZIP alignment.
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile
import zipfile


def check_load_segments(output: str, name: str) -> list[str]:
    loads = [line.split() for line in output.splitlines() if line.strip().startswith('LOAD ')]
    if not loads:
        return [f'{name}: no ELF LOAD segments found']
    failures = []
    for fields in loads:
        try:
            align = int(fields[-1], 0)
        except ValueError:
            failures.append(f'{name}: cannot parse alignment: {" ".join(fields)}')
            continue
        if align < 16384 or align % 16384 != 0:
            failures.append(f'{name}: LOAD alignment {align:#x} is not 16 KiB compatible')
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('apk')
    parser.add_argument('readelf')
    args = parser.parse_args()
    failures = []
    with zipfile.ZipFile(args.apk) as apk, tempfile.TemporaryDirectory() as temp:
        libraries = [name for name in apk.namelist() if name.startswith('lib/') and name.endswith('.so')]
        if not libraries:
            print('No APK native libraries found', file=sys.stderr)
            return 1
        for index, name in enumerate(sorted(libraries)):
            path = pathlib.Path(temp) / f'{index}.so'
            path.write_bytes(apk.read(name))
            result = subprocess.run([args.readelf, '-lW', str(path)], text=True, capture_output=True)
            if result.returncode:
                failures.append(f'{name}: llvm-readelf failed: {result.stderr}')
                continue
            print(f'=== {name} ===')
            for line in result.stdout.splitlines():
                if line.strip().startswith('LOAD '):
                    print(line.strip())
            failures.extend(check_load_segments(result.stdout, name))
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f'All {len(libraries)} native libraries have 16 KiB compatible LOAD alignment.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
