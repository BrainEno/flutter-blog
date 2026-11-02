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

flutter_pin() {
  local file="$PROJECT_ROOT/tool/flutter_version.txt"
  [[ -f "$file" ]] || fail 'Missing tool/flutter_version.txt, which records the pinned Flutter SDK.'
  tr -d '[:space:]' < "$file"
}

# One comparison for every entry point. CI and release packaging require the
# pinned SDK exactly; local debug only needs a Dart SDK that satisfies
# pubspec.yaml, because being unable to start the emulator is a worse outcome
# than a version drift the developer can see and decide about.
_check_flutter_version() {
  local strict="$1" version_json pinned
  pinned="$(flutter_pin)"
  version_json="$(flutter --version --machine)" \
    || fail 'Could not query the Flutter SDK. Run `flutter --version` and `flutter doctor` to see the SDK error.'
  FLUTTER_VERSION_JSON="$version_json" \
    PINNED_FLUTTER_VERSION="$pinned" \
    BELOG_STRICT_FLUTTER_VERSION="$strict" \
    PROJECT_ROOT="$PROJECT_ROOT" \
    python3 - <<'PY'
import json, os, re, sys

pin = os.environ["PINNED_FLUTTER_VERSION"]
try:
    payload = json.loads(os.environ["FLUTTER_VERSION_JSON"])
except ValueError:
    sys.exit("Could not parse `flutter --version --machine` output.")
framework = str(payload.get("frameworkVersion") or "")
dart = str(payload.get("dartSdkVersion") or "")
if framework == pin:
    sys.exit(0)


def version_parts(text):
    match = re.match(r"\s*(\d+(?:\.\d+)*)", text)
    return tuple(int(part) for part in match.group(1).split(".")) if match else ()


def at_least(actual, minimum):
    have, need = version_parts(actual), version_parts(minimum)
    if not have or not need:
        return None
    width = max(len(have), len(need))
    return have + (0,) * (width - len(have)) >= need + (0,) * (width - len(need))


dart_floor = ""
pubspec = os.path.join(os.environ["PROJECT_ROOT"], "pubspec.yaml")
try:
    with open(pubspec, encoding="utf-8") as handle:
        for line in handle:
            declared = re.match(r'\s*sdk:\s*"([^"]+)"', line)
            if declared:
                floor = re.search(r">=\s*([0-9][0-9.]*)", declared.group(1))
                dart_floor = floor.group(1) if floor else ""
                break
except OSError:
    dart_floor = ""

compatible = at_least(dart, dart_floor) if dart and dart_floor else None
strict = os.environ.get("BELOG_STRICT_FLUTTER_VERSION") == "1"

if strict or compatible is False:
    found = framework + (f" (Dart {dart})" if dart else "")
    print(f"Error: Flutter {pin} is required; found {found}.", file=sys.stderr)
    if compatible is False:
        print(f"pubspec.yaml requires Dart {dart_floor} or newer; this SDK does not satisfy it.", file=sys.stderr)
    print("Upgrade the SDK: flutter upgrade", file=sys.stderr)
    print("If that reports \"upstream branch 'refs/heads/stable' not stored as a remote-tracking branch\",", file=sys.stderr)
    print("repair the SDK's own Git clone first, then upgrade:", file=sys.stderr)
    print('  git -C "<path-to-flutter-sdk>" fetch origin stable', file=sys.stderr)
    print('  git -C "<path-to-flutter-sdk>" branch --set-upstream-to=origin/stable stable', file=sys.stderr)
    print("  flutter upgrade", file=sys.stderr)
    print(f"Or install Flutter {pin} and put it first on PATH.", file=sys.stderr)
    sys.exit(1)

print(f"Warning: Flutter {framework} is installed; CI and release builds use {pin}.")
if compatible is None:
    print("Warning: could not compare this SDK with pubspec.yaml's Dart constraint.")
print("Local debug continues; it only needs a compatible Dart SDK.")
print("Set BELOG_STRICT_FLUTTER_VERSION=1 to require the pinned SDK.")
PY
}

# Debug entry points: drift is a warning unless the caller opts into strictness.
check_flutter_version() { _check_flutter_version "${BELOG_STRICT_FLUTTER_VERSION:-0}"; }

# Release packaging: the artifact must match what CI verifies.
require_pinned_flutter_version() { _check_flutter_version 1; }

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
