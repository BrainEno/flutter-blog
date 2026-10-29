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
  .github/workflows/ci.yml
  .github/workflows/dart.yml
  tool/ci/check_env_asset_contract.sh
  tool/ci/annotate_failure.sh
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
  for token in 'pull_request:' 'permissions:' 'flutter analyze --fatal-infos' 'flutter test --coverage' 'flutter build apk --release' 'upload-artifact@'; do
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
fi
release="$root/.github/workflows/dart.yml"
if [[ -f "$release" ]]; then
  for forbidden in 'svenstaro/upload-release-action' 'tag: v1.9' 'overwrite: true'; do
    if grep -Fq -- "$forbidden" "$release"; then
      echo "::error::Unsafe legacy release behavior remains in dart.yml: $forbidden"
      failed=1
    fi
  done
fi
if (( failed )); then exit 1; fi
echo 'Agent development contract and workflow guardrails are present.'
