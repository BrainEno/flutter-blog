#!/usr/bin/env bash
# Record a cancellation as itself, not as a build failure.
#
# A macOS native job that the runner killed and a job that failed to compile
# both render as one red cross. Those two answers send a contributor in
# opposite directions - read the diff, or re-run and note the infrastructure -
# so the distinction has to be written down while the platform still lets this
# job speak. It is best-effort by design: a hard runner loss never reaches a
# step, which is why the workflow keeps its `timeout-minutes` as the backstop.
set -euo pipefail

label="${1:-this job}"
summary="${GITHUB_STEP_SUMMARY:-}"

text=$(
  cat <<EOF
### \`$label\` was cancelled; it did not fail

The run was cancelled while this job was in progress. No build step reported an
error, so this is **not** evidence about the diff.

- Superseded by a newer commit on a pull request: expected. Read the newest run
  for this head SHA instead; \`main\` pushes are never superseded (see
  \`docs/ci-observability.md\`).
- Cancelled with nothing newer pushed: treat it as runner infrastructure.
  Re-run the job once. If it is cancelled again, record it in the CI-signal
  issue, not in the pull request, and do not add \`continue-on-error\`.
EOF
)

if [[ -n "$summary" ]]; then
  printf '%s\n' "$text" >>"$summary"
fi

printf '%s\n' "$text"
