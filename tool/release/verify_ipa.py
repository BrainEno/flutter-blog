#!/usr/bin/env python3
"""Validate an AltStore re-signable IPA, not a directly installable app.

This checks the archive, iOS device bundle, privacy descriptions and identity.
It does not prove AltStore signing, installation, backend connectivity or audio
on a physical device. Native binary architecture/signatures are checked on macOS
by the packaging workflow, separately from this portable metadata verifier.
"""

import argparse
import plistlib
import posixpath
import stat
import sys
import zipfile

APP = 'Payload/Runner.app'
REQUIRED_ENTRIES = (
    f'{APP}/Info.plist',
    f'{APP}/Runner',
    f'{APP}/Frameworks/Flutter.framework/Flutter',
    f'{APP}/Frameworks/App.framework/App',
    f'{APP}/en.lproj/InfoPlist.strings',
    f'{APP}/zh-Hans.lproj/InfoPlist.strings',
)


def verify(ipa: str, bundle_id: str, build_name: str, build_number: str) -> None:
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError('IPA contains duplicate entries.')
        for entry in entries:
            name = entry.filename
            if (name.startswith('/') or '\\' in name or
                    any(part == '..' for part in name.split('/'))):
                raise ValueError('Unsafe IPA entry path.')
            if entry.flag_bits & 1:
                raise ValueError('IPA contains an encrypted entry.')
            if stat.S_ISLNK(entry.external_attr >> 16):
                target = archive.read(entry).decode('utf-8')
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if (target.startswith('/') or '\\' in target or resolved == '..' or
                        resolved.startswith('../')):
                    raise ValueError('Unsafe IPA symlink.')
        top_level = sorted({name.split('/', 1)[0] for name in names if name})
        if top_level != ['Payload']:
            raise ValueError(f'IPA must contain only a Payload/ directory, found: {top_level}')
        bundles = sorted({name.split('/')[1] for name in names
                          if name.startswith('Payload/') and name.count('/') >= 2})
        if bundles != ['Runner.app']:
            raise ValueError(f'Payload/ must contain exactly Runner.app, found: {bundles}')
        for required in REQUIRED_ENTRIES:
            if required not in names:
                raise ValueError(f'Missing required entry: {required}')
        if any(name.endswith('/embedded.mobileprovision') for name in names):
            raise ValueError('Unexpected embedded provisioning profile in AltStore input.')
        if any('.appex/' in name or name.endswith('.appex') for name in names):
            raise ValueError('App extensions require a separately reviewed AltStore signing policy.')
        if archive.testzip() is not None:
            raise ValueError('IPA archive contains a corrupt entry.')
        info = plistlib.loads(archive.read(f'{APP}/Info.plist'))
        checks = (
            ('CFBundleIdentifier', bundle_id),
            ('CFBundleShortVersionString', build_name),
            ('CFBundleVersion', build_number),
            ('CFBundleExecutable', 'Runner'),
            ('CFBundlePackageType', 'APPL'),
            ('LSRequiresIPhoneOS', True),
        )
        for key, expected in checks:
            actual = info.get(key)
            if actual != expected:
                raise ValueError(f'Info.plist {key}: expected {expected!r}, found {actual!r}')
        if 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
            raise ValueError('IPA does not contain an iPhoneOS device build.')
        if not info.get('UISupportedInterfaceOrientations'):
            raise ValueError('Info.plist UISupportedInterfaceOrientations is empty')
        for key in ('NSPhotoLibraryUsageDescription', 'NSCameraUsageDescription'):
            if not isinstance(info.get(key), str) or not info[key].strip():
                raise ValueError(f'Info.plist {key} is missing or empty.')
        if info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads') is True:
            raise ValueError('Release IPA must not permit arbitrary cleartext HTTP.')
        print(f'IPA entries: {len(names)}')
        print(f'CFBundleIdentifier: {info.get("CFBundleIdentifier")}')
        print(f'CFBundleShortVersionString: {info.get("CFBundleShortVersionString")}')
        print(f'CFBundleVersion: {info.get("CFBundleVersion")}')
        print(f'CFBundleDisplayName: {info.get("CFBundleDisplayName")}')
        print('iPhoneOS device build and privacy descriptions present.')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', help='path to the .ipa file')
    parser.add_argument('bundle_id', help='expected CFBundleIdentifier')
    parser.add_argument('build_name', help='expected CFBundleShortVersionString')
    parser.add_argument('build_number', help='expected CFBundleVersion')
    args = parser.parse_args()
    try:
        verify(args.ipa, args.bundle_id, args.build_name, args.build_number)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError,
            zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f'::error::IPA verification failed: {error}', file=sys.stderr)
        return 1
    print('IPA structure, identity and version verified.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
