#!/usr/bin/env bash
# CI-only checks: the generated keystore/passwords are disposable test fixtures.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/test_verify_apk.sh"
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
expected="$(keytool -exportcert -keystore "$ANDROID_KEYSTORE_PATH" -storepass "$ANDROID_KEYSTORE_PASSWORD" -alias "$ANDROID_KEY_ALIAS" | sha256sum | cut -d' ' -f1)"
version="$(sed -n 's/^version: *\([^ #]*\).*/\1/p' pubspec.yaml)"
name="${version%+*}"
number="${version##*+}"
APK=build/app/outputs/flutter-apk/app-release.apk
if ! bash tool/release/verify_apk.sh "$APK" "$name" "$number" "$expected"; then
  # These certificates belong only to the disposable CI keystore and QA build.
  # Distinguish a stale QA-signed APK from a verifier/parsing failure.
  echo '::error::Disposable signing fixture did not produce the expected APK certificate.'
  echo "Expected test certificate SHA-256: $expected"
  echo 'Actual test APK certificates:'
  "$TOOLS/apksigner" verify --print-certs "$APK"
  echo 'Prior QA APK certificates:'
  "$TOOLS/apksigner" verify --print-certs build/reports/belog-QA-debug-signed.apk
  exit 1
fi
if bash tool/release/verify_apk.sh "$APK" "$name" "$number" "$(printf '%064d' 0)" > "$RUNNER_TEMP/mismatch.log" 2>&1; then
  echo '::error::An APK with a mismatched signing certificate was accepted.'; exit 1
fi
grep -Fq 'fingerprint does not match' "$RUNNER_TEMP/mismatch.log"
QA_APK=build/reports/belog-QA-debug-signed.apk
"$TOOLS/apksigner" verify --print-certs "$QA_APK" > "$RUNNER_TEMP/qa-cert.txt"
# shellcheck source=tool/release/apk_certificate.sh
source "$(dirname "${BASH_SOURCE[0]}")/apk_certificate.sh"
qa_cert="$(read_apk_signer_sha256 "$RUNNER_TEMP/qa-cert.txt")"
if bash tool/release/verify_apk.sh "$QA_APK" "$name" "$number" "$qa_cert" > "$RUNNER_TEMP/debug-cert.log" 2>&1; then
  echo '::error::A debug-signed APK was accepted for release.'; exit 1
fi
grep -Fq 'Debug signing certificate is not allowed' "$RUNNER_TEMP/debug-cert.log"
rm -f "$ANDROID_KEYSTORE_PATH"
echo 'Unsigned, mismatched and debug-signed releases rejected; CI-only signing verified.'
