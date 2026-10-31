#!/usr/bin/env python3
"""Check the identity/version of an Xcode-exported IPA before presenting it."""

import plistlib
import posixpath
import stat
import sys
import zipfile


def main():
    path, bundle_id, build_name, build_number = sys.argv[1:]
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            # The build script extracts this archive for codesign verification.
            # Reject paths and symlinks that could escape that temporary dir.
            for entry in archive.infolist():
                name = entry.filename
                if (name.startswith('/') or '\\' in name or
                        any(part == '..' for part in name.split('/'))):
                    raise ValueError('Unsafe IPA entry path.')
                if stat.S_ISLNK(entry.external_attr >> 16):
                    target = archive.read(entry).decode('utf-8')
                    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                    if target.startswith('/') or '\\' in target or resolved == '..' or resolved.startswith('../'):
                        raise ValueError('Unsafe IPA symlink.')
            apps = {name.split('/')[1] for name in names if name.startswith('Payload/') and name.count('/') >= 2}
            if apps != {'Runner.app'}:
                raise ValueError('Expected exactly Payload/Runner.app.')
            for required in ('Payload/Runner.app/Runner', 'Payload/Runner.app/Info.plist',
                             'Payload/Runner.app/Frameworks/Flutter.framework/Flutter',
                             'Payload/Runner.app/Frameworks/App.framework/App'):
                if required not in names:
                    raise ValueError(f'Missing {required}.')
            info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
            expected = {'CFBundleIdentifier': bundle_id, 'CFBundleShortVersionString': build_name,
                        'CFBundleVersion': build_number, 'CFBundleExecutable': 'Runner',
                        'CFBundlePackageType': 'APPL', 'LSRequiresIPhoneOS': True}
            for key, value in expected.items():
                if info.get(key) != value:
                    raise ValueError(f'Unexpected {key} in exported IPA.')
            if archive.testzip() is not None:
                raise ValueError('IPA archive contains a corrupt entry.')
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f'IPA verification failed: {error}', file=sys.stderr)
        return 1
    print('IPA structure, bundle ID and version verified; certificate/provisioning still require device verification.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
