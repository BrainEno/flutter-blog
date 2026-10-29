#!/usr/bin/env bash
# Fail if a .env file is tracked or declared as a Flutter asset.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pubspec="$root/pubspec.yaml"
gitignore="$root/.gitignore"

if [[ ! -f "$pubspec" ]]; then
  echo '::error::pubspec.yaml is missing.'
  exit 1
fi
if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo '::error::Unable to inspect tracked files: not a git worktree.'
  exit 1
fi

failed=0
env_asset=0
# Match the same literal four-space-indented .env asset entry, with optional
# quotes and comment, rather than matching documentation or .env.example.
if grep -Eq '^[[:space:]]{4}-[[:space:]]*["'"'"']?\.env["'"'"']?[[:space:]]*(#.*)?$' "$pubspec"; then
  env_asset=1
  echo '::error::pubspec.yaml bundles .env as a Flutter asset. Remove it and use explicit compile-time configuration injection (Issue #2).'
  failed=1
fi
if ! tracked_env="$(git -C "$root" ls-files -- .env)"; then
  echo '::error::Unable to inspect tracked files.'
  exit 1
fi
if [[ -n "$tracked_env" ]]; then
  echo '::error::A .env file is tracked by git. Remove it from version control and rotate any credentials that were exposed.'
  failed=1
fi
if (( env_asset )) && [[ -f "$gitignore" ]] && grep -Eq '^\.env/?$' "$gitignore"; then
  echo '::error::.env is ignored by .gitignore but is still declared as an asset; a clean clone cannot reproduce this asset.'
  failed=1
fi
if (( failed )); then exit 1; fi
echo 'Environment asset contract passed: no bundled .env and no tracked .env.'
