#!/usr/bin/env python3
"""Write checksums and non-secret provenance alongside a mobile artifact."""
import argparse
import hashlib
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('kind', choices=('ios-altstore', 'android-personal', 'android-debug'))
    parser.add_argument('build_name')
    parser.add_argument('build_number')
    args = parser.parse_args()
    digest = hashlib.sha256()
    with args.artifact.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    summary = {
        'ios-altstore': 'Ad-hoc only; AltStore must re-sign with your personal Apple ID.',
        'android-personal': 'Signed with the owner-supplied Android certificate.',
        'android-debug': 'Debuggable, temporary debug certificate; not a production release.',
    }[args.kind]
    directory = args.artifact.parent
    with (directory / 'SHA256SUMS.txt').open('x', encoding='utf-8') as stream:
        stream.write(f'{digest.hexdigest()}  {args.artifact.name}\n')
    with (directory / 'BUILD-INFO.txt').open('x', encoding='utf-8') as stream:
        stream.write(f'Kind: {args.kind}\nVersion: {args.build_name}+{args.build_number}\n'
                     f'Source commit: {os.environ.get("GITHUB_SHA", "unknown")}\n'
                     f'GitHub run: {os.environ.get("GITHUB_RUN_ID", "unknown")}\n'
                     f'Run attempt: {os.environ.get("GITHUB_RUN_ATTEMPT", "unknown")}\n'
                     f'{summary}\n'
                     'Backend reachability and physical-device installation were not tested by CI.\n')
    print('SHA-256 checksum and non-secret provenance created.')


if __name__ == '__main__':
    main()
