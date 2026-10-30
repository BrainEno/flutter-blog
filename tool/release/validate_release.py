#!/usr/bin/env python3
"""Validate release inputs without printing client keys or signing material."""

import ipaddress
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

TAG = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)\Z")


def validate_version(tag: str, pubspec: str) -> tuple[str, str]:
    match = TAG.fullmatch(tag)
    versions = re.findall(r"(?m)^version:\s*([^\s#]+)\s*(?:#.*)?$", pubspec)
    if not match or len(versions) != 1 or versions[0] != tag[1:]:
        raise ValueError("Tag must be vMAJOR.MINOR.PATCH+BUILD and match pubspec.yaml exactly.")
    if int(match[4]) > 2100000000:
        raise ValueError("Android version code exceeds 2100000000.")
    return ".".join(match.group(i) for i in (1, 2, 3)), match[4]


def validate_api_base_url(url: str) -> None:
    try:
        uri = urlsplit(url)
        host = uri.hostname or ""
        if (uri.scheme != "https" or not host or uri.username or uri.password or
                uri.query or uri.fragment or host == "localhost" or
                host in ("example.com", "example.org", "example.net") or
                host.endswith((".invalid", ".example", ".test", ".localhost"))):
            raise ValueError
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            address = None
        if address is not None and not address.is_global:
            raise ValueError
    except ValueError:
        raise ValueError("API_BASE_URL must be a real HTTPS endpoint.") from None


def main() -> int:
    try:
        tag = os.environ.get("GITHUB_REF_NAME", "")
        name, number = validate_version(tag, Path("pubspec.yaml").read_text())
        if os.environ.get("ANDROID_APPLICATION_ID_APPROVED") != "com.example.belog":
            raise ValueError("Owner must explicitly approve the existing Android application ID before publishing.")
        cert = os.environ.get("ANDROID_RELEASE_CERT_SHA256", "")
        if not re.fullmatch(r"[0-9A-Fa-f]{64}", cert):
            raise ValueError("ANDROID_RELEASE_CERT_SHA256 must be the expected 64-digit certificate SHA-256.")
        if not all(os.environ.get(k, "").strip() for k in ("ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")):
            raise ValueError("All Android release signing secrets are required.")
        if os.environ["ANDROID_KEY_ALIAS"].lower() == "androiddebugkey":
            raise ValueError("The Android debug key cannot be used for production signing.")
        url = os.environ.get("API_BASE_URL", "")
        validate_api_base_url(url)
        config = Path(os.environ["RUNNER_TEMP"]) / "belog-release-env.json"
        fd = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump({"API_BASE_URL": url}, stream)
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write(f"build_name={name}\nbuild_number={number}\n")
    except (ValueError, OSError, KeyError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
