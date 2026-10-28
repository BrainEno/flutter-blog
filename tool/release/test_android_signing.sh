#!/usr/bin/env bash
# CI-only checks: the generated keystore/passwords are disposable test fixtures.
set -euo pipefail
unset ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD
if BELOG_QA_BUILD=false flutter build apk --release --dart-define-from-file=env.json > "$RUNNER_TEMP/missing-signing.log" 2>&1; then
  echo '::error::A release build succeeded without signing credentials.'
  exit 1
fi
if ! grep -Fq 'Release signing credentials are required' "$RUNNER_TEMP/missing-signing.log"; then
  echo '::error::Release failed for an unexpected reason; see diagnostic output below.'
  tail -40 "$RUNNER_TEMP/missing-signing.log"
  exit 1
fi
export ANDROID_KEYSTORE_PATH="$RUNNER_TEMP/ci-only.keystore"
export ANDROID_KEYSTORE_PASSWORD=ci-only-password
export ANDROID_KEY_ALIAS=ci-only
export ANDROID_KEY_PASSWORD=ci-only-password
keytool -genkeypair -keystore "$ANDROID_KEYSTORE_PATH" -storepass "$ANDROID_KEYSTORE_PASSWORD" \
  -alias "$ANDROID_KEY_ALIAS" -keypass "$ANDROID_KEY_PASSWORD" -dname 'CN=CI Test Only' \
  -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1
BELOG_QA_BUILD=false flutter build apk --release --dart-define-from-file=env.json > "$RUNNER_TEMP/ci-signed-build.log" 2>&1 || {
  tail -80 "$RUNNER_TEMP/ci-signed-build.log"
  exit 1
}
TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
"$TOOLS/apksigner" verify --print-certs build/app/outputs/flutter-apk/app-release.apk > "$RUNNER_TEMP/ci-cert.txt"
grep -F 'CN=CI Test Only' "$RUNNER_TEMP/ci-cert.txt" >/dev/null
rm -f "$ANDROID_KEYSTORE_PATH"
echo 'Unsigned release rejected and CI-only production signing fixture verified.'
