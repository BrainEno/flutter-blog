#!/bin/bash
# Shared macOS helpers. The entry points set -euo pipefail.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing $1. Install the required tools described in README.md."
}

require_macos() {
  [[ "$(uname -s)" == Darwin ]] || fail 'This script requires macOS with Xcode.'
  require_command python3
  require_command flutter
  require_command xcrun
  require_command xcodebuild
  xcodebuild -version >/dev/null || fail 'Select a working full Xcode installation with xcode-select.'
}

check_flutter_version() {
  local version_json
  version_json="$(flutter --version --machine)" || fail 'Could not query the Flutter SDK.'
  printf '%s' "$version_json" | python3 -c '
import json, sys
try:
    version = json.load(sys.stdin)["frameworkVersion"]
except (ValueError, KeyError, TypeError):
    sys.exit("Could not parse flutter --version --machine.")
if version != "3.47.8":
    sys.exit("Flutter 3.47.8 is required; found " + str(version) + ".")
' || fail 'Select the repository-pinned Flutter 3.47.8 SDK.'
}

resolve_config() {
  local path="$1"
  [[ "$path" = /* ]] || path="$PROJECT_ROOT/$path"
  [[ -f "$path" ]] || fail 'Config not found. Copy env.example.json to env.json and edit the public API origin.'
  # Preserve spaces in the original path; do not print or copy its contents.
  CONFIG_PATH="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
}

validate_config() {
  local platform="$1" mode="$2"
  if [[ "$mode" == release ]]; then
    python3 "$SCRIPT_DIR/validate_config.py" "$CONFIG_PATH" --platform "$platform" --release
  else
    python3 "$SCRIPT_DIR/validate_config.py" "$CONFIG_PATH" --platform "$platform"
  fi
}
