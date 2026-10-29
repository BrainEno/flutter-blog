#!/usr/bin/env python3
"""Verify that the APK contains the exact rebuilt legacy migration reader."""
import pathlib
import sys
import zipfile


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: check_legacy_apk.py APK JNI_LIBS_DIR')
    apk_path, directory = sys.argv[1:]
    with zipfile.ZipFile(apk_path) as apk:
        entries = [name for name in apk.namelist() if name.startswith('lib/') and name.endswith('/libisar.so')]
        flutter_abis = {name.split('/')[1] for name in apk.namelist()
                        if name.startswith('lib/') and name.endswith('/libflutter.so')}
        legacy_abis = {name.split('/')[1] for name in entries}
        if not flutter_abis or legacy_abis != flutter_abis:
            raise SystemExit(f'Legacy reader ABIs {sorted(legacy_abis)} do not match Flutter ABIs {sorted(flutter_abis)}')
        for name in entries:
            abi = name.split('/')[1]
            expected = pathlib.Path(directory, abi, 'libisar.so')
            if not expected.is_file() or apk.read(name) != expected.read_bytes():
                raise SystemExit(f'APK contains an unexpected legacy reader: {name}')
            print(f'Verified rebuilt legacy reader: {name}')


if __name__ == '__main__':
    main()
