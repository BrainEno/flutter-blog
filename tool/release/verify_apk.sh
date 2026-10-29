#!/usr/bin/env bash
# Verify an APK against independently approved release metadata.
set -euo pipefail
if (( $# != 4 )); then
  echo 'Usage: verify_apk.sh APK BUILD_NAME BUILD_NUMBER CERT_SHA256' >&2
  exit 2
fi
APK=$1
BUILD_NAME=$2
BUILD_NUMBER=$3
EXPECTED_CERT=$4
if [[ ! "$EXPECTED_CERT" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo 'Invalid expected certificate fingerprint.' >&2
  exit 1
fi
TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
test -f "$APK" && test -x "$TOOLS/apksigner" && test -x "$TOOLS/aapt"
cert_file="$(mktemp "${RUNNER_TEMP:-/tmp}/belog-cert.XXXXXX")"
badging_file="$(mktemp "${RUNNER_TEMP:-/tmp}/belog-badging.XXXXXX")"
trap 'rm -f "$cert_file" "$badging_file"' EXIT
"$TOOLS/apksigner" verify --verbose --print-certs "$APK" > "$cert_file"
if [[ "$(grep -c 'certificate SHA-256 digest:' "$cert_file")" != 1 ]]; then
  echo 'APK must have exactly one signing certificate.' >&2
  exit 1
fi
actual="$(awk -F ': ' '/Signer #1 certificate SHA-256 digest:/ {print tolower($2)}' "$cert_file")"
if [[ "$actual" != "${EXPECTED_CERT,,}" ]]; then
  echo 'APK certificate fingerprint does not match the approved certificate.' >&2
  exit 1
fi
if grep -qi 'certificate DN:.*CN=Android Debug' "$cert_file"; then
  echo 'Debug signing certificate is not allowed for release.' >&2
  exit 1
fi
"$TOOLS/aapt" dump badging "$APK" > "$badging_file"
grep -F "package: name='com.example.belog' versionCode='$BUILD_NUMBER' versionName='$BUILD_NAME'" "$badging_file" >/dev/null
grep -F 'android.permission.INTERNET' "$badging_file" >/dev/null
echo 'APK signature, package ID, version and INTERNET permission verified.'
