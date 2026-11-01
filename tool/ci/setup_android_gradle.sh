#!/usr/bin/env bash
# CI-only Gradle user home. Do not modify the developer's Gradle settings.
set -euo pipefail
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"

if [[ "$RUNNER_TEMP" == *$'\n'* || "$RUNNER_TEMP" == *$'\r'* ]]; then
  echo 'Gradle home must be a single-line path.' >&2
  exit 1
fi
umask 077
gradle_home="$(mktemp -d "$RUNNER_TEMP/belog-ci-gradle.XXXXXXXX")"
# A private, fresh CI home makes the setting deterministic and prevents a
# host-level Gradle property from silently overriding it. The project's 4 GiB
# JVM heap setting still applies; dependency and build caches live here too.
printf 'org.gradle.workers.max=1\n' > "$gradle_home/gradle.properties"
printf 'GRADLE_USER_HOME=%s\n' "$gradle_home" >> "$GITHUB_ENV"
echo 'Configured an isolated Gradle user home with one worker for this CI job.'
