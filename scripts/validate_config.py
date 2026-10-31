#!/usr/bin/env python3
"""Validate the public dart-define file without printing its contents."""

import argparse
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit

ALLOWED_KEYS = {"API_BASE_URL", "WEB_BASE_URL"}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate configuration key.")
        result[key] = value
    return result


def validate_origin(value, name, *, https_only=False):
    if not isinstance(value, str) or not value or any(c.isspace() for c in value):
        raise ValueError(f"{name} must be a non-empty HTTP(S) origin.")
    try:
        uri = urlsplit(value)
        host = (uri.hostname or "").lower()
        _ = uri.port  # Also reject an invalid port without echoing the value.
        if (uri.scheme not in ("http", "https") or not host or uri.username or
                uri.password or uri.path not in ("", "/") or uri.query or
                uri.fragment or (https_only and uri.scheme != "https") or
                host in ("example.com", "example.org", "example.net") or
                host.endswith((".example.com", ".example.org", ".example.net",
                               ".example", ".invalid", ".test"))):
            raise ValueError
    except ValueError:
        suffix = "HTTPS" if https_only else "HTTP(S)"
        raise ValueError(f"{name} must be a real {suffix} origin, with no credentials, path, query or fragment.") from None
    return uri


def validate(path, *, platform, release):
    try:
        with Path(path).open(encoding="utf-8-sig") as stream:
            config = json.load(stream, object_pairs_hook=unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("Cannot read config JSON. Copy env.example.json to env.json and edit the public origins.") from error
    if not isinstance(config, dict) or not set(config).issubset(ALLOWED_KEYS):
        raise ValueError("Config may contain only API_BASE_URL and WEB_BASE_URL; never embed secrets in a client build.")
    api = validate_origin(config.get("API_BASE_URL"), "API_BASE_URL", https_only=release)
    web = config.get("WEB_BASE_URL", "")
    if web != "":
        validate_origin(web, "WEB_BASE_URL", https_only=release)
    if platform == "android" and api.hostname in ("localhost", "127.0.0.1", "::1"):
        print("Warning: localhost inside the Android emulator is not the host. Use 10.0.2.2 for a host-local API.")
    if api.scheme == "http":
        print("Warning: HTTP is allowed only by the debug app and sends credentials unencrypted. Use a trusted local backend.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    try:
        validate(args.path, platform=args.platform, release=args.release)
    except ValueError as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 1
    print("Public client configuration OK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
