#!/usr/bin/env bash
# Build and validate the AltStore input IPA (not a directly installable IPA).
set -euo pipefail
if (( $# != 3 )); then
  echo 'Usage: build_ios_package.sh CONFIG BUILD_NAME BUILD_NUMBER' >&2
  exit 2
fi
CONFIG=$1
BUILD_NAME=$2
BUILD_NUMBER=$3
test -f "$CONFIG"
bash scripts/build_ios_ipa.sh --config "$CONFIG" --mode altstore --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
count=0
IPA=''
while IFS= read -r -d '' item; do
  IPA="$item"
  count=$((count + 1))
done < <(find build/ios/local-ipa -maxdepth 1 -type f -name '*.ipa' -print0)
[[ "$count" == 1 ]] || { echo 'Expected exactly one new IPA in this clean CI checkout.' >&2; exit 1; }
python3 tool/release/verify_ipa.py "$IPA" com.nodeman24.belog "$BUILD_NAME" "$BUILD_NUMBER"
tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/belog-ios-check.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
ditto -x -k "$IPA" "$tmp"
APP="$tmp/Payload/Runner.app"
for executable in "$APP/Runner" "$APP/Frameworks/Flutter.framework/Flutter" "$APP/Frameworks/App.framework/App"; do
  xcrun lipo "$executable" -verify_arch arm64
done
# Ensure this is an iPhoneOS device binary, rather than an arm64 simulator build.
xcrun vtool -show-build "$APP/Runner" > "$tmp/platform.txt"
grep -Eq 'platform[[:space:]]+IOS([[:space:]]|$)' "$tmp/platform.txt" || {
  echo 'Main executable is not an iOS device Mach-O.' >&2
  exit 1
}
codesign --verify --deep --strict --verbose "$APP"
mkdir -p build/mobile/ios
OUTPUT=build/mobile/ios/BottomThink-ios-altstore-resign-required.ipa
[[ ! -e "$OUTPUT" ]] || { echo 'Refusing to overwrite an existing artifact.' >&2; exit 1; }
cp "$IPA" "$OUTPUT"
python3 tool/mobile/artifact_metadata.py "$OUTPUT" ios-altstore "$BUILD_NAME" "$BUILD_NUMBER"
echo 'Validated AltStore input IPA; device installation requires personal Apple ID re-signing.'
