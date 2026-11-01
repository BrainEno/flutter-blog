#!/usr/bin/env bash
# Exercise the CI scripts in an isolated temporary git repository.
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tool/ci" "$tmp/docs" "$tmp/.github/workflows"
cp "$source_root"/tool/ci/*.sh "$tmp/tool/ci/"
cp "$source_root/AGENTS.md" "$source_root/pubspec.yaml" "$source_root/.gitignore" "$tmp/"
cp "$source_root"/docs/*.md "$tmp/docs/"
cp "$source_root/.github/pull_request_template.md" "$tmp/.github/"
cp "$source_root"/.github/workflows/*.yml "$tmp/.github/workflows/"
git -C "$tmp" init -q

expect_failure() {
  local expected="$1"; shift
  local output
  if output="$("$@" 2>&1)"; then
    echo "Expected failure from: $*" >&2
    exit 1
  fi
  if ! grep -Fq -- "$expected" <<<"$output"; then
    echo "Missing expected diagnostic: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

env_check="$tmp/tool/ci/check_env_asset_contract.sh"
agent_check="$tmp/tool/ci/validate_agent_contract.sh"
annotation="$tmp/tool/ci/annotate_failure.sh"
bash "$env_check" >/dev/null
bash "$agent_check" >/dev/null

# Positive and negative cases for secret/configuration checks.
cp "$tmp/pubspec.yaml" "$tmp/pubspec.original"
printf '\n    - .env.example\n    # - .env\n' >> "$tmp/pubspec.yaml"
bash "$env_check" >/dev/null
for asset in '.env' '".env"' "'.env'"; do
  cp "$tmp/pubspec.original" "$tmp/pubspec.yaml"
  printf '\n    - %s # fixture\n' "$asset" >> "$tmp/pubspec.yaml"
  expect_failure 'bundles .env' bash "$env_check"
done
cp "$tmp/pubspec.original" "$tmp/pubspec.yaml"
printf 'fixture only\n' > "$tmp/.env"
git -C "$tmp" add -f .env
expect_failure 'tracked by git' bash "$env_check"
git -C "$tmp" rm --cached -q -- .env
cp "$tmp/.git/index" "$tmp/index.backup"
printf 'invalid index' > "$tmp/.git/index"
expect_failure 'Unable to inspect tracked files' bash "$env_check"
cp "$tmp/index.backup" "$tmp/.git/index"
rm "$tmp/pubspec.yaml"
expect_failure 'pubspec.yaml is missing' bash "$env_check"
cp "$tmp/pubspec.original" "$tmp/pubspec.yaml"
mv "$tmp/.git" "$tmp/git-dir"
expect_failure 'not a git worktree' bash "$env_check"
mv "$tmp/git-dir" "$tmp/.git"

# Guardrails must still reject missing contracts, unsafe triggers and releases.
mv "$tmp/AGENTS.md" "$tmp/AGENTS.backup"
expect_failure 'Required agent/CI file is missing: AGENTS.md' bash "$agent_check"
mv "$tmp/AGENTS.backup" "$tmp/AGENTS.md"
sed -i 's/## Completion report/## Removed/' "$tmp/AGENTS.md"
expect_failure 'missing required section: ## Completion report' bash "$agent_check"
cp "$source_root/AGENTS.md" "$tmp/AGENTS.md"
ci="$tmp/.github/workflows/ci.yml"
cp "$ci" "$tmp/ci.original"
printf '\n  pull_request_target:\n' >> "$ci"
expect_failure 'must not use pull_request_target' bash "$agent_check"
cp "$tmp/ci.original" "$ci"
printf '\n  continue-on-error: true\n' >> "$ci"
expect_failure 'must not be forced green' bash "$agent_check"
cp "$tmp/ci.original" "$ci"
sed -i 's/flutter test --coverage/flutter test/' "$ci"
expect_failure 'missing expected guardrail/check: flutter test --coverage' bash "$agent_check"
cp "$tmp/ci.original" "$ci"
printf '\noverwrite: true\n' >> "$tmp/.github/workflows/dart.yml"
expect_failure 'Unsafe legacy release behavior' bash "$agent_check"
cp "$source_root/.github/workflows/dart.yml" "$tmp/.github/workflows/dart.yml"
rm "$tmp/tool/ci/check_env_asset_contract.sh"
expect_failure 'Required agent/CI file is missing: tool/ci/check_env_asset_contract.sh' bash "$agent_check"

# Bounded annotations must retain context, deduplicate overlaps, and escape
# workflow command characters (including CR/LF) without dumping unrelated logs.
printf 'before\nerror: 10%%\r\nCaused by: problem\nafter\n' > "$tmp/log"
output="$(bash "$annotation" android "$tmp/log")"
[[ "$output" == '::error title=android failure diagnostics::before%0Aerror: 10%25%0D%0ACaused by: problem%0Aafter' ]]
output="$(bash "$annotation" analyze "$tmp/log")"
[[ "$output" == '::error title=analyze failure diagnostics::before%0Aerror: 10%25%0D%0ACaused by: problem%0Aafter' ]]
printf 'nothing interesting\n' > "$tmp/log"
output="$(bash "$annotation" android "$tmp/log")"
[[ "$output" == '::error title=android failure diagnostics::No matching diagnostics; inspect the uploaded log artifact.' ]]
awk 'BEGIN { for (i=1; i<=105; i++) print "line " i }' > "$tmp/log"
output="$(bash "$annotation" analyze "$tmp/log")"
[[ "$output" == *'::line 6%0Aline 7'* && "$output" != *'line 5%0A'* && "$output" == *'line 105' ]]
# GitHub truncates annotation messages at 4096 bytes; the script caps at
# 3600 (keeping the tail, where crash summaries live) so nothing important
# is cut by the platform.
awk 'BEGIN { for (i=1; i<=25000; i++) printf "x"; print "END" }' > "$tmp/log"
output="$(bash "$annotation" analyze "$tmp/log")"
message="${output#*diagnostics::}"
[[ ${#message} == 3600 && "$message" == *END ]]
expect_failure 'Usage:' bash "$annotation" unknown "$tmp/log"
expect_failure 'not readable' bash "$annotation" analyze "$tmp/missing"

# CI uses a private temporary Gradle home, not a developer's settings. Verify
# the real GitHub environment file protocol and fail closed if inputs are absent.
mkdir -p "$tmp/runner with spaces" "$tmp/home/.gradle"
printf 'developer.setting=preserve\n' > "$tmp/home/.gradle/gradle.properties"
printf 'EXISTING=kept\n' > "$tmp/github-env"
env HOME="$tmp/home" RUNNER_TEMP="$tmp/runner with spaces" GITHUB_ENV="$tmp/github-env" \
  bash "$tmp/tool/ci/setup_android_gradle.sh" >/dev/null
ci_gradle_home="$(sed -n 's/^GRADLE_USER_HOME=//p' "$tmp/github-env")"
[[ "$ci_gradle_home" == "$tmp/runner with spaces/belog-ci-gradle."* ]]
grep -Fxq 'EXISTING=kept' "$tmp/github-env"
grep -Fxq 'org.gradle.workers.max=1' "$ci_gradle_home/gradle.properties"
grep -Fxq 'developer.setting=preserve' "$tmp/home/.gradle/gradle.properties"
: > "$tmp/github-env-2"
env HOME="$tmp/home" RUNNER_TEMP="$tmp/runner with spaces" GITHUB_ENV="$tmp/github-env-2" \
  bash "$tmp/tool/ci/setup_android_gradle.sh" >/dev/null
second_gradle_home="$(sed -n 's/^GRADLE_USER_HOME=//p' "$tmp/github-env-2")"
[[ "$ci_gradle_home" != "$second_gradle_home" && -f "$ci_gradle_home/gradle.properties" ]]
expect_failure 'RUNNER_TEMP is required' env -u RUNNER_TEMP GITHUB_ENV="$tmp/github-env" bash "$tmp/tool/ci/setup_android_gradle.sh"
expect_failure 'GITHUB_ENV is required' env -u GITHUB_ENV RUNNER_TEMP="$tmp/runner" bash "$tmp/tool/ci/setup_android_gradle.sh"
expect_failure 'single-line path' env RUNNER_TEMP="$tmp/runner"$'\n''bad' GITHUB_ENV="$tmp/github-env" bash "$tmp/tool/ci/setup_android_gradle.sh"

# The debug Android gate verifies the effective Gradle limit, starts a fresh
# daemon and retains both manifest policies. Mocks need no Android SDK.
mkdir -p "$tmp/bin" "$tmp/android" "$tmp/sdk/build-tools/36.0.0" "$tmp/build/app/outputs/flutter-apk"
cat > "$tmp/android/gradlew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gradle:$*" >> "$MOCK_CALLS"
case "$*" in
  '--info help')
    if [[ "${MOCK_GRADLE_FAIL:-0}" == 1 ]]; then
      echo 'synthetic Gradle probe failure' >&2
      exit 13
    fi
    echo "Using ${MOCK_WORKERS:-1} worker leases."
    ;;
  '--stop')
    if [[ "${MOCK_STOP_FAIL:-0}" == 1 ]]; then
      echo 'synthetic Gradle stop failure' >&2
      exit 14
    fi
    echo 'Stopped the fixture daemon.'
    ;;
  *) exit 2 ;;
esac
EOF
cat > "$tmp/bin/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *'build apk --debug'* && "$*" == *'BELOG_DEV_BACKEND_CHECK=true'* ]] || exit 2
echo 'flutter:debug' >> "$MOCK_CALLS"
if [[ "${MOCK_BUILD_FAIL:-0}" == 1 ]]; then
  echo 'synthetic debug build failure' >&2
  exit 7
fi
if [[ "${MOCK_MISSING_DEBUG:-0}" != 1 ]]; then
  touch build/app/outputs/flutter-apk/app-debug.apk
fi
EOF
cat > "$tmp/sdk/build-tools/36.0.0/aapt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$3" == *app-debug.apk ]]; then
  if [[ "${MOCK_DEBUG_DISALLOWS:-0}" == 1 ]]; then
    echo 'android:usesCleartextTraffic 0x0'
  else
    echo 'android:usesCleartextTraffic 0xffffffff'
  fi
elif [[ "$3" == *app-release.apk ]]; then
  if [[ "${MOCK_RELEASE_ALLOWS:-0}" == 1 ]]; then
    echo 'android:usesCleartextTraffic 0xffffffff'
  else
    echo 'no cleartext opt-in'
  fi
else
  exit 2
fi
EOF
chmod +x "$tmp/bin/flutter" "$tmp/sdk/build-tools/36.0.0/aapt"
touch "$tmp/build/app/outputs/flutter-apk/app-release.apk"
run_android_debug_fixture() {
  (cd "$tmp" && env PATH="$tmp/bin:$PATH" ANDROID_HOME="$tmp/sdk" MOCK_CALLS="$tmp/debug-calls" "$@" bash tool/ci/check_android_debug.sh)
}
: > "$tmp/debug-calls"
run_android_debug_fixture >/dev/null
printf 'gradle:--info help\ngradle:--stop\nflutter:debug\n' > "$tmp/debug-expected-calls"
cmp "$tmp/debug-expected-calls" "$tmp/debug-calls"
: > "$tmp/debug-calls"
expect_failure 'Gradle did not report the required single worker' run_android_debug_fixture MOCK_WORKERS=2
! grep -Fq 'flutter:debug' "$tmp/debug-calls"
: > "$tmp/debug-calls"
expect_failure 'synthetic Gradle probe failure' run_android_debug_fixture MOCK_GRADLE_FAIL=1
! grep -Fq 'flutter:debug' "$tmp/debug-calls"
: > "$tmp/debug-calls"
expect_failure 'synthetic Gradle stop failure' run_android_debug_fixture MOCK_STOP_FAIL=1
! grep -Fq 'flutter:debug' "$tmp/debug-calls"
expect_failure 'synthetic debug build failure' run_android_debug_fixture MOCK_BUILD_FAIL=1
for case_and_status in MOCK_GRADLE_FAIL=1:13 MOCK_STOP_FAIL=1:14 MOCK_BUILD_FAIL=1:7; do
  flag="${case_and_status%:*}"
  expected_status="${case_and_status##*:}"
  actual_status=0
  run_android_debug_fixture "$flag" >/dev/null 2>&1 || actual_status=$?
  [[ "$actual_status" == "$expected_status" ]]
done
expect_failure 'Debug manifest must explicitly allow' run_android_debug_fixture MOCK_DEBUG_DISALLOWS=1
expect_failure 'Release manifest must not allow' run_android_debug_fixture MOCK_RELEASE_ALLOWS=1
rm "$tmp/build/app/outputs/flutter-apk/app-debug.apk"
expect_failure 'Expected debug and release APKs' run_android_debug_fixture MOCK_MISSING_DEBUG=1
rm "$tmp/android/gradlew"
expect_failure 'Gradle wrapper is missing' run_android_debug_fixture

echo 'CI script tests passed.'
