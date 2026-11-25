#!/usr/bin/env bash
# Validate agent-workflow guardrails using tools already present on CI runners.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failed=0
required_files=(
  AGENTS.md
  docs/agent-development.md
  docs/ci-observability.md
  .github/pull_request_template.md
  .github/dependabot.yml
  .github/workflows/ci.yml
  .github/workflows/dart.yml
  tool/ci/check_env_asset_contract.sh
  tool/ci/annotate_failure.sh
  tool/ci/summarize_cancellation.sh
  tool/ci/test_ci_scripts.sh
)
for path in "${required_files[@]}"; do
  if [[ ! -f "$root/$path" ]]; then
    echo "::error::Required agent/CI file is missing: $path"
    failed=1
  fi
done

require_section() {
  local path="$1" section="$2"
  if [[ -f "$root/$path" ]] && ! grep -Fq -- "$section" "$root/$path"; then
    echo "::error::$path is missing required section: $section"
    failed=1
  fi
}
for section in '## Repository workflow' '## Commands and evidence' '## Secrets, configuration and external services' '## Completion report'; do
  require_section AGENTS.md "$section"
done
for section in '## 1. Intake and scope' '## 3. Validate and capture evidence' '## 4. Pull Request protocol'; do
  require_section docs/agent-development.md "$section"
done
for section in '## Validation layers' '## Interpreting failures' '## Debugging a failure'; do
  require_section docs/ci-observability.md "$section"
done
for section in '## Related issue' '## Validation evidence' '## Security and privacy'; do
  require_section .github/pull_request_template.md "$section"
done

ci="$root/.github/workflows/ci.yml"
if [[ -f "$ci" ]]; then
  for token in 'pull_request:' 'permissions:' 'dart format --output=none --set-exit-if-changed .' 'flutter analyze --fatal-infos' 'flutter test --coverage' 'flutter build apk --release' 'upload-artifact@'; do
    if ! grep -Fq -- "$token" "$ci"; then
      echo "::error::CI workflow is missing expected guardrail/check: $token"
      failed=1
    fi
  done
  if grep -Fq 'pull_request_target:' "$ci"; then
    echo '::error::CI must not use pull_request_target for untrusted code.'
    failed=1
  fi
  if grep -Fq 'continue-on-error: true' "$ci"; then
    echo '::error::Critical quality checks must not be forced green with continue-on-error.'
    failed=1
  fi
  if grep -Fq 'non-blocking until legacy formatting debt' "$ci"; then
    echo '::error::Repository-wide Dart formatting must be a blocking CI gate.'
    failed=1
  fi
fi
# A workflow that verifies `main` must not compete with the next verification of
# `main`: an unconditional `cancel-in-progress: true` on a push-to-main trigger
# cancels the run that a merge just earned, so a red or cancelled check stops
# carrying any information about the diff. Jobs on that path are also bounded,
# because a wedged runner holding a check open for hours removes evidence in the
# same way. Where a macOS or Windows runner is involved, the job must also say
# out loud that a cancellation is not a build failure.
for workflow in "$root"/.github/workflows/*.yml; do
  name="$(basename "$workflow")"
  if ! awk '
    /^on:/ { on = 1; next }
    on && /^jobs:/ { exit }
    on && /^  push:/ { push = 1; next }
    on && push && /branches:/ && /main/ { found = 1; exit }
    END { if (found) exit 0; exit 1 }
  ' "$workflow"; then
    continue
  fi
  if awk '
    /^concurrency:/ { c = 1; next }
    c && /^[^[:space:]]/ { exit }
    c && /^  cancel-in-progress:[[:space:]]*true[[:space:]]*$/ { found = 1 }
    END { if (found) exit 0; exit 1 }
  ' "$workflow"; then
    echo "::error::$name runs on push to main but cancels in-progress runs unconditionally; gate cancel-in-progress on github.event_name (see docs/ci-observability.md)."
    failed=1
  fi
  while IFS= read -r job; do
    echo "::error::$name job '$job' runs on the main verification path without timeout-minutes."
    failed=1
  done < <(awk '
    /^jobs:/ { jobs = 1; next }
    jobs && /^  [A-Za-z0-9_-]+:$/ {
      if (job != "" && !bounded) print job
      job = $1
      sub(/:$/, "", job)
      bounded = 0
      next
    }
    jobs && /^    timeout-minutes:/ { bounded = 1 }
    END { if (job != "" && !bounded) print job }
  ' "$workflow")
  if grep -Eq 'macos-latest|windows-latest' "$workflow" &&
    ! grep -Fq 'tool/ci/summarize_cancellation.sh' "$workflow"; then
    echo "::error::$name builds on a macOS/Windows runner without a cancellation step; a cancelled job must be distinguishable from a failed one."
    failed=1
  fi
done

release="$root/.github/workflows/dart.yml"
if [[ -f "$release" ]]; then
  for forbidden in 'svenstaro/upload-release-action' 'tag: v1.9' 'overwrite: true'; do
    if grep -Fq -- "$forbidden" "$release"; then
      echo "::error::Unsafe legacy release behavior remains in dart.yml: $forbidden"
      failed=1
    fi
  done
  if grep -Fq 'pull_request:' "$release"; then
    echo '::error::dart.yml must be manually dispatched; ci.yml owns PR Android release validation.'
    failed=1
  fi
  if ! grep -Fq 'workflow_dispatch:' "$release"; then
    echo '::error::dart.yml must retain its explicit manual validation trigger.'
    failed=1
  fi
fi
dependabot="$root/.github/dependabot.yml"
if [[ -f "$dependabot" ]]; then
  for token in 'package-ecosystem: pub' 'package-ecosystem: github-actions' 'interval: weekly'; do
    if ! grep -Fq -- "$token" "$dependabot"; then
      echo "::error::Dependabot configuration is missing expected update policy: $token"
      failed=1
    fi
  done
fi
if (( failed )); then exit 1; fi
echo 'Agent development contract and workflow guardrails are present.'
