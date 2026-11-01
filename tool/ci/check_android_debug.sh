#!/usr/bin/env bash
# Compile the debug variant and verify the debug/release cleartext policies.
# CI runs this only with its disconnected public configuration fixture.
set -euo pipefail

mkdir -p build/reports
if [[ ! -f android/gradlew ]]; then
  echo 'error: The Flutter-generated Android Gradle wrapper is missing.' >&2
  exit 1
fi
# The release/signing checks precede this step. Verify Gradle actually picked
# up the CI worker limit, then stop that daemon so debug begins with a fresh
# heap rather than inheriting several release builds' in-memory state.
echo 'Checking the effective Gradle worker limit.'
set +e
(cd android && bash ./gradlew --info help) > build/reports/gradle-worker-check.log 2>&1
status=$?
set -e
if (( status != 0 )); then
  echo 'error: Gradle worker verification failed.' >&2
  tail -n 80 build/reports/gradle-worker-check.log >&2
  exit "$status"
fi
if ! grep -Fq 'Using 1 worker leases.' build/reports/gradle-worker-check.log; then
  echo 'error: Gradle did not report the required single worker.' >&2
  tail -n 80 build/reports/gradle-worker-check.log >&2
  exit 1
fi
echo 'Stopping the previous Gradle daemon before debug compilation.'
(cd android && bash ./gradlew --stop)

echo 'Building the Android debug APK.'
flutter build apk --debug --dart-define-from-file=env.json --dart-define=BELOG_DEV_BACKEND_CHECK=true

AAPT="$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -n 1)"
if [[ -z "$AAPT" ]]; then
  echo 'error: Android aapt was not found.' >&2
  exit 1
fi
DEBUG_APK=build/app/outputs/flutter-apk/app-debug.apk
RELEASE_APK=build/app/outputs/flutter-apk/app-release.apk
if [[ ! -f "$DEBUG_APK" || ! -f "$RELEASE_APK" ]]; then
  echo 'error: Expected debug and release APKs are not both present.' >&2
  exit 1
fi

echo 'Checking the Android debug and release manifests.'
"$AAPT" dump xmltree "$DEBUG_APK" AndroidManifest.xml > build/reports/android-debug-manifest.txt
"$AAPT" dump xmltree "$RELEASE_APK" AndroidManifest.xml > build/reports/android-release-manifest.txt
if ! grep -E 'android:usesCleartextTraffic.*0xffffffff' build/reports/android-debug-manifest.txt; then
  echo 'error: Debug manifest must explicitly allow development cleartext traffic.' >&2
  exit 1
fi
if grep -E 'android:usesCleartextTraffic.*0xffffffff' build/reports/android-release-manifest.txt; then
  echo 'error: Release manifest must not allow cleartext traffic.' >&2
  exit 1
fi
echo 'Android debug build and both network policies verified.'
