#!/bin/bash
# Finder double-click entry point; defaults to the AltStore ad-hoc IPA.
exec "$(cd "$(dirname "$0")" && pwd)/build_ios_ipa.sh" "$@"
