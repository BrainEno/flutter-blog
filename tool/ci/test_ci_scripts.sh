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
echo 'CI script tests passed.'
