#!/usr/bin/env python3
"""Verify the structure and metadata of the AltStore sideload IPA.

Checks that the artifact is a proper `Payload/Runner.app` bundle with the
Flutter framework layout and an Info.plist matching the release identity.
Runs anywhere with Python 3 (uses only the standard library), so the same
check runs in unit tests and in the release workflow.
"""

import argparse
import plistlib
import sys
import zipfile

APP = 'Payload/Runner.app'
REQUIRED_ENTRIES = (
    f'{APP}/Info.plist',
    f'{APP}/Runner',
    f'{APP}/Frameworks/Flutter.framework/Flutter',
    f'{APP}/Frameworks/App.framework/App',
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', help='path to the .ipa file')
    parser.add_argument('bundle_id', help='expected CFBundleIdentifier')
    parser.add_argument('build_name', help='expected CFBundleShortVersionString')
    parser.add_argument('build_number', help='expected CFBundleVersion')
    args = parser.parse_args()

    failures = []
    try:
        archive = zipfile.ZipFile(args.ipa)
    except (OSError, zipfile.BadZipFile) as error:
        print(f'::error::Cannot open IPA {args.ipa}: {error}')
        return 1
    with archive:
        names = archive.namelist()
        top_level = sorted({name.split('/', 1)[0] for name in names if name})
        if top_level != ['Payload']:
            failures.append(
                f'IPA must contain only a Payload/ directory, found: {top_level}',
            )
        bundles = sorted(
            {
                name.split('/')[1]
                for name in names
                if name.startswith('Payload/') and name.count('/') >= 2
            },
        )
        if bundles != ['Runner.app']:
            failures.append(
                f'Payload/ must contain exactly Runner.app, found: {bundles}',
            )
        for required in REQUIRED_ENTRIES:
            if required not in names:
                failures.append(f'Missing required entry: {required}')
        if failures:
            for failure in failures:
                print(f'::error::{failure}')
            return 1
        info = plistlib.loads(archive.read(f'{APP}/Info.plist'))
        checks = (
            ('CFBundleIdentifier', args.bundle_id),
            ('CFBundleShortVersionString', args.build_name),
            ('CFBundleVersion', args.build_number),
            ('CFBundleExecutable', 'Runner'),
            ('CFBundlePackageType', 'APPL'),
            ('LSRequiresIPhoneOS', True),
        )
        for key, expected in checks:
            actual = info.get(key)
            if actual != expected:
                failures.append(
                    f'Info.plist {key}: expected {expected!r}, found {actual!r}',
                )
        orientations = info.get('UISupportedInterfaceOrientations') or []
        if not orientations:
            failures.append('Info.plist UISupportedInterfaceOrientations is empty')
        print(f'IPA entries: {len(names)}')
        print(f'CFBundleIdentifier: {info.get("CFBundleIdentifier")}')
        print(f'CFBundleShortVersionString: {info.get("CFBundleShortVersionString")}')
        print(f'CFBundleVersion: {info.get("CFBundleVersion")}')
        print(f'CFBundleDisplayName: {info.get("CFBundleDisplayName")}')
        print(f'UISupportedInterfaceOrientations: {len(orientations)}')
    if failures:
        for failure in failures:
            print(f'::error::{failure}')
        return 1
    print('IPA structure, identity and version verified.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
