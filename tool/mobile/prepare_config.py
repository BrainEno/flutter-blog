#!/usr/bin/env python3
"""Create a public dart-define file for the manual mobile packaging workflow.

PR validation gets a deliberately unreachable fixture. A manual build must use
main and real HTTPS origins supplied as non-secret inputs/repository variables.
The script validates syntax, not DNS, TLS, service deployment or compatibility.
"""

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.validate_config import validate_origin  # noqa: E402
from tool.release.validate_release import validate_api_base_url, validate_version  # noqa: E402


def public_origin(value: str, name: str) -> None:
    # Together these reject paths, queries, userinfo, placeholders, HTTP,
    # localhost and non-global IP literals. Device reachability is not implied.
    uri = validate_origin(value, name, https_only=True)
    try:
        validate_api_base_url(value)
        host = (uri.hostname or '').rstrip('.').lower()
        if host == 'localhost' or host.endswith('.localhost'):
            raise ValueError
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            if re.fullmatch(r'[0-9.]+', host):
                raise ValueError
        else:
            if not address.is_global:
                raise ValueError
    except ValueError:
        raise ValueError(f'{name} must be a public HTTPS origin, not a placeholder or loopback.') from None


def build_metadata(pubspec: str, run_number: str, requested_number: str) -> tuple[str, str]:
    versions = re.findall(r'(?m)^version:\s*([^\s#]+)\s*(?:#.*)?$', pubspec)
    if len(versions) != 1:
        raise ValueError('pubspec.yaml must have exactly one version: MAJOR.MINOR.PATCH+BUILD.')
    name, base_number = validate_version('v' + versions[0], pubspec)
    number = requested_number or run_number
    if not re.fullmatch(r'[1-9][0-9]*', number or ''):
        raise ValueError('Build number must be a positive integer.')
    if int(number) < int(base_number) or int(number) > 2100000000:
        raise ValueError('Build number must be at least the pubspec build number and at most 2100000000.')
    return name, number


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', help='new private temporary JSON path')
    args = parser.parse_args()
    try:
        event = os.environ.get('GITHUB_EVENT_NAME', '')
        if event == 'pull_request':
            # Never upload this config as an installable personal artifact.
            api, web = 'https://127.0.0.1', ''
            target, mode = 'both', 'personal'
            requested = ''
        elif event == 'workflow_dispatch':
            if os.environ.get('GITHUB_REF') != 'refs/heads/main':
                raise ValueError('Personal packages must be built from the main branch.')
            api = os.environ.get('PUBLIC_API_ORIGIN', '')
            web = os.environ.get('PUBLIC_WEB_ORIGIN', '')
            public_origin(api, 'API_BASE_URL')
            if web:
                public_origin(web, 'WEB_BASE_URL')
            target = os.environ.get('INPUT_TARGET', '')
            mode = os.environ.get('INPUT_ANDROID_MODE', '')
            requested = os.environ.get('INPUT_BUILD_NUMBER', '')
            if target not in ('both', 'ios', 'android') or mode not in ('personal', 'debug'):
                raise ValueError('Unknown target or Android signing mode.')
        else:
            raise ValueError('Only pull-request validation and manual builds are supported.')
        name, number = build_metadata(Path('pubspec.yaml').read_text(),
                                      os.environ.get('GITHUB_RUN_NUMBER', ''), requested)
        config = {'API_BASE_URL': api, 'WEB_BASE_URL': web}
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            json.dump(config, stream)
        output = os.environ.get('GITHUB_OUTPUT')
        if output:
            with open(output, 'a', encoding='utf-8') as stream:
                stream.write(f'build_name={name}\nbuild_number={number}\ntarget={target}\nandroid_mode={mode}\n'
                             f'api_origin={api}\nweb_origin={web}\n')
        print('Public client configuration and build metadata validated; backend reachability was not tested.')
    except (ValueError, OSError, KeyError) as error:
        print(f'::error::{error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
