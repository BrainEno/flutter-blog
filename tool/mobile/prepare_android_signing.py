#!/usr/bin/env python3
"""Validate and decode an owner-supplied Android keystore to a new private file.

All values arrive through the job environment, never command-line arguments.
Only ephemeral CI fixture values may be used during pull-request tests.
"""

import argparse
import base64
import binascii
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tool.release.validate_release import validate_android_signing  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', help='new temporary keystore path')
    args = parser.parse_args()
    try:
        validate_android_signing(os.environ)
        encoded = re.sub(r'\s+', '', os.environ['ANDROID_KEYSTORE_BASE64'])
        if len(encoded) > 7_000_000:
            raise ValueError('Android keystore input is unexpectedly large.')
        try:
            data = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError('ANDROID_KEYSTORE_BASE64 is not valid base64.') from None
        if not data:
            raise ValueError('Android keystore is empty.')
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
    except (ValueError, OSError, KeyError) as error:
        print(f'::error::{error}', file=sys.stderr)
        return 1
    print('Android signing inputs validated; a private temporary keystore was created.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
