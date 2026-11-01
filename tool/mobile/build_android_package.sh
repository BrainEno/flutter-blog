#!/usr/bin/env bash
# Shared real build path for CI fixture signing and owner-requested APKs.
set -euo pipefail
if (( $# != 5 )); then
  echo 'Usage: build_android_package.sh CONFIG BUILD_NAME BUILD_NUMBER personal|debug EXPECTED_CERT_OR_DASH' >&2
  exit 2
fi
CONFIG=$1
BUILD_NAME=$2
BUILD_NUMBER=$3
MODE=$4
EXPECTED_CERT=$5
[[ "$MODE" == personal || "$MODE" == debug ]] || { echo 'Invalid Android package mode.' >&2; exit 1; }
test -f "$CONFIG"
flutter pub get
if [[ "$MODE" == personal ]]; then
  export BELOG_QA_BUILD=false
  flutter build apk --release --dart-define-from-file="$CONFIG" --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
  APK=build/app/outputs/flutter-apk/app-release.apk
  NAME=BottomThink-android-personal-signed.apk
else
  flutter build apk --debug --dart-define-from-file="$CONFIG" --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
  APK=build/app/outputs/flutter-apk/app-debug.apk
  NAME=BottomThink-android-debug-temporary-key.apk
fi
bash tool/mobile/verify_android_package.sh "$APK" "$BUILD_NAME" "$BUILD_NUMBER" "$MODE" "$EXPECTED_CERT"
OUTPUT_DIR="build/mobile/android/$MODE"
mkdir -p "$OUTPUT_DIR"
[[ ! -e "$OUTPUT_DIR/$NAME" ]] || { echo 'Refusing to overwrite an existing artifact.' >&2; exit 1; }
cp "$APK" "$OUTPUT_DIR/$NAME"
python3 tool/mobile/artifact_metadata.py "$OUTPUT_DIR/$NAME" "android-$MODE" "$BUILD_NAME" "$BUILD_NUMBER"
