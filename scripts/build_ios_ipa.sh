#!/bin/bash
# Local IPA build. Default: ad-hoc AltStore sideload package, NOT store-signed.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/build_ios_ipa.sh [--config env.json] [--mode altstore|signed]
       [--export-options /path/ExportOptions.plist] [--build-name X.Y.Z] [--build-number N]
Default is an ad-hoc IPA for AltStore to re-sign; it is not App Store/TestFlight signed.
Signed mode requires your own Xcode team, certificate, provisioning and export-options plist.
EOF
}

config=env.json
mode=altstore
export_options=''
build_name=''
build_number=''
while (($#)); do
  case "$1" in
    --config|--mode|--export-options|--build-name|--build-number)
      [[ $# -ge 2 ]] || fail "Missing value for $1."
      case "$1" in
        --config) config="$2" ;;
        --mode) mode="$2" ;;
        --export-options) export_options="$2" ;;
        --build-name) build_name="$2" ;;
        --build-number) build_number="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[[ "$mode" == altstore || "$mode" == signed ]] || fail 'Mode must be altstore or signed.'
if [[ "$mode" == signed ]]; then
  [[ -n "$export_options" && -f "$export_options" ]] || fail 'Signed mode requires an existing --export-options plist and Xcode signing configuration.'
  export_options="$(cd "$(dirname "$export_options")" && pwd)/$(basename "$export_options")"
elif [[ -n "$export_options" ]]; then
  fail '--export-options is only valid in signed mode.'
fi
require_macos
require_command codesign
require_command ditto
require_command zip
check_flutter_version
resolve_config "$config"
# Release/profile builds do not have the debug HTTP exception.
validate_config ios release
cd "$PROJECT_ROOT"

version="$(awk '$1 == "version:" {print $2}' pubspec.yaml)"
[[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]] || fail 'pubspec.yaml must contain one version: MAJOR.MINOR.PATCH+BUILD.'
[[ -n "$build_name" ]] || build_name="${BASH_REMATCH[1]}"
[[ -n "$build_number" ]] || build_number="${BASH_REMATCH[2]}"
[[ "$build_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Build name must be MAJOR.MINOR.PATCH.'
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail 'Build number must be a positive integer.'

stage="$(mktemp -d "${TMPDIR:-/tmp}/belog-ipa.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
flutter pub get
set -- --release "--dart-define-from-file=$CONFIG_PATH" "--build-name=$build_name" "--build-number=$build_number"

if [[ "$mode" == altstore ]]; then
  flutter build ios "$@" --no-codesign
  original="$PROJECT_ROOT/build/ios/iphoneos/Runner.app"
  [[ -d "$original/Frameworks" ]] || fail 'Flutter did not produce the expected device Runner.app and Frameworks.'
  mkdir -p "$stage/Payload"
  # Sign only our temporary copy; never alter an existing user build.
  ditto "$original" "$stage/Payload/Runner.app"
  app="$stage/Payload/Runner.app"
  find "$app/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -exec codesign --force --sign - {} \;
  codesign --force --sign - "$app"
  codesign --verify --verbose "$app"
  (cd "$stage" && zip -qry "$stage/candidate.ipa" Payload)
  candidate="$stage/candidate.ipa"
  python3 "$PROJECT_ROOT/tool/release/verify_ipa.py" "$candidate" com.nodeman24.belog "$build_name" "$build_number"
else
  marker="$stage/build-started"
  : > "$marker"
  flutter build ipa "$@" "--export-options-plist=$export_options"
  ipa_dir="$PROJECT_ROOT/build/ios/ipa"
  [[ -d "$ipa_dir" ]] || fail 'Xcode did not produce an IPA export directory.'
  count=0
  candidate=''
  while IFS= read -r -d '' item; do
    candidate="$item"
    count=$((count + 1))
  done < <(find "$ipa_dir" -maxdepth 1 -type f -name '*.ipa' -newer "$marker" -print0)
  [[ "$count" == 1 ]] || fail 'Expected exactly one newly exported IPA; refusing to use a stale or ambiguous artifact.'
  python3 "$SCRIPT_DIR/verify_signed_ipa.py" "$candidate" com.nodeman24.belog "$build_name" "$build_number"
  mkdir -p "$stage/extracted"
  ditto -x -k "$candidate" "$stage/extracted"
  codesign --verify --deep --strict --verbose "$stage/extracted/Payload/Runner.app"
fi

output_dir="$PROJECT_ROOT/build/ios/local-ipa"
mkdir -p "$output_dir"
output="$output_dir/belog-${build_name}+${build_number}-${mode}-$(date +%Y%m%d-%H%M%S)-$$.ipa"
[[ ! -e "$output" ]] || fail 'The output file already exists; refusing to overwrite it.'
# A signed candidate is still in Flutter's output; copy, never move/overwrite it.
cp "$candidate" "$output"
printf '\nIPA created: %s\n' "$output"
if [[ "$mode" == altstore ]]; then
  printf '%s\n' 'Ad-hoc only: install via AltStore, which re-signs with your Apple ID. Not an App Store/TestFlight distribution IPA.'
else
  printf '%s\n' 'Exported with your local Xcode signing settings. Certificate, provisioning and device installation have not been independently verified.'
fi
