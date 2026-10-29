#!/usr/bin/env bash
# Add a bounded diagnostic excerpt to a GitHub Actions error annotation.
#
# For `analyze` (also reused for the test step) the excerpt keeps, in file
# order: every failing-test progress line (marked with `[E]`), the full
# "EXCEPTION CAUGHT" blocks, and the trailing 100 lines as before. For
# `android` the original error-context window is kept. The message cap is
# unchanged (last 24000 bytes-equivalent kept).
set -euo pipefail
if [[ $# != 2 || ( "$1" != analyze && "$1" != android ) ]]; then
  echo 'Usage: annotate_failure.sh {analyze|android} LOG_FILE' >&2
  exit 2
fi
if [[ ! -r "$2" ]]; then
  echo 'Diagnostic log is not readable.' >&2
  exit 1
fi

awk -v mode="$1" '
  {
    lines[NR] = $0
    if (mode == "android") {
      lower = tolower($0)
      if (lower ~ /failure: build failed|what went wrong:|execution failed for task|(^|[^[:alnum:]_])error:|caused by:|requires.*compilesdk|android resource linking failed/) {
        for (i = NR - 1; i <= NR + 4; i++) if (i > 0) selected[i] = 1
      }
    }
  }
  END {
    has_failures = 0
    if (mode == "analyze") {
      # Failing-test progress lines carry "[E]" at the end; keep the line
      # before each for context (usually the preceding progress step) plus
      # the indented detail lines that follow (Expected:/Actual: blocks,
      # stack excerpts) until the next progress or summary line.
      for (i = 1; i <= NR; i++)
        if (lines[i] ~ /\[E\][[:space:]]*$/) {
          has_failures = 1
          selected[i] = 1
          if (i > 1) selected[i - 1] = 1
          for (j = i + 1; j <= NR && j <= i + 14; j++) {
            if (lines[j] ~ /^[[:space:]]/ || lines[j] ~ /^[-=]+$/) {
              selected[j] = 1
            } else {
              break
            }
          }
        }
      # Load/crash summaries (no [E] progress line exists for these).
      for (i = 1; i <= NR; i++)
        if (lines[i] ~ /Failed to load|Some tests failed|Fatal error|Unhandled exception|Test failed/) {
          has_failures = 1
          for (j = i; j <= NR && j <= i + 12; j++) selected[j] = 1
        }

      # Full exception blocks: two lines of lead-in, the bordered banner,
      # and everything up to (and including) the closing border line of
      # box-drawing characters, bounded per block.
      in_exc = 0
      exc_len = 0
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /EXCEPTION CAUGHT/) {
          in_exc = 1
          exc_len = 0
          for (j = i - 2; j < i; j++) if (j > 0) selected[j] = 1
        }
        if (in_exc) {
          selected[i] = 1
          exc_len++
          if (exc_len >= 30) in_exc = 0
          else if (i > 1 && lines[i] ~ /^[═══=][═══=]+$/ && lines[i - 1] !~ /EXCEPTION CAUGHT/) in_exc = 0
        }
      }
      # Unchanged trailing window: the last 100 lines.
      for (i = NR - 99; i <= NR; i++) if (i > 0) selected[i] = 1
    }
    message = ""
    count = 0
    for (i = 1; i <= NR; i++) {
      if (selected[i]) {
        message = message (count++ ? "\n" : "") lines[i]
      }
    }
    if (has_failures) {
      # GitHub caps annotation messages at 4096 bytes; the failing tests and
      # their details matter more than the trailing window.
      if (length(message) > 3600) message = substr(message, 1, 3600)
    } else if (length(message) > 3600) {
      # Without [E] progress lines the failure is a load/crash summary that
      # lives at the END of the log; keep the tail, not the head.
      message = substr(message, length(message) - 3599)
    }
    if (message == "") message = "No matching diagnostics; inspect the uploaded log artifact."
    gsub(/%/, "%25", message)
    gsub(/\r/, "%0D", message)
    gsub(/\n/, "%0A", message)
    printf "::error title=%s failure diagnostics::%s\n", mode, message
  }
' "$2"
