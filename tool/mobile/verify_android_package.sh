#!/usr/bin/env bash
# Verify the actual APK; personal mode requires an independently approved key.
set -euo pipefail
if (( $# != 5 )); then
  echo 'Usage: verify_android_package.sh APK BUILD_NAME BUILD_NUMBER personal|debug EXPECTED_CERT_OR_DASH' >&2
  exit 2
fi
APK=$1
BUILD_NAME=$2
BUILD_NUMBER=$3
MODE=$4
EXPECTED_CERT=$5
[[ "$MODE" == personal || "$MODE" == debug ]] || { echo 'Invalid Android package mode.' >&2; exit 1; }
TOOLS="$(find "${ANDROID_HOME:?ANDROID_HOME is required}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
for command in apksigner aapt zipalign; do test -x "$TOOLS/$command"; done
test -f "$APK"
tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/belog-apk-check.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
"$TOOLS/apksigner" verify --verbose --print-certs "$APK" > "$tmp/cert.txt"
"$TOOLS/aapt" dump badging "$APK" > "$tmp/badging.txt"
"$TOOLS/aapt" dump permissions "$APK" > "$tmp/permissions.txt"
"$TOOLS/aapt" dump xmltree "$APK" AndroidManifest.xml > "$tmp/manifest.txt"
grep -F "package: name='com.nodeman24.nowave' versionCode='$BUILD_NUMBER' versionName='$BUILD_NAME'" "$tmp/badging.txt" >/dev/null
for permission in android.permission.INTERNET android.permission.ACCESS_NETWORK_STATE; do
  if ! grep -Fq "uses-permission: name='$permission'" "$tmp/permissions.txt"; then
    echo "Required permission missing from final APK: $permission" >&2
    exit 1
  fi
done
if [[ "$MODE" == personal ]]; then
  bash "$(dirname "$0")/../release/verify_apk.sh" "$APK" "$BUILD_NAME" "$BUILD_NUMBER" "$EXPECTED_CERT"
  if grep -q '^application-debuggable' "$tmp/badging.txt" ||
     grep -E -q 'android:usesCleartextTraffic.*0xffffffff' "$tmp/manifest.txt"; then
    echo 'Personal release APK must not be debuggable or allow cleartext traffic.' >&2
    exit 1
  fi
  READELF="$(find "$ANDROID_HOME/ndk" -name llvm-readelf -path '*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf' | sort -V | tail -n 1)"
  test -x "$READELF"
  python3 "$(dirname "$0")/../ci/check_apk_16k.py" "$APK" "$READELF"
  "$TOOLS/zipalign" -c -P 16 -v 4 "$APK" >/dev/null
else
  grep -q '^application-debuggable' "$tmp/badging.txt" || { echo 'Expected a debuggable APK.' >&2; exit 1; }
fi
python3 - "$APK" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    names = set(archive.namelist())
    for abi in ('arm64-v8a', 'armeabi-v7a'):
        if f'lib/{abi}/libflutter.so' not in names:
            raise SystemExit(f'Missing Flutter engine for {abi} in universal APK.')
    if archive.testzip() is not None:
        raise SystemExit('APK has a corrupt ZIP entry.')
print('APK archive and ARM 32/64-bit Flutter engines verified.')
PY
echo 'Final APK identity, signature, version and required network permissions verified.'
