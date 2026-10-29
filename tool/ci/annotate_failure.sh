#!/usr/bin/env bash
# Add a bounded diagnostic excerpt to a GitHub Actions error annotation.
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
    message = ""
    count = 0
    for (i = 1; i <= NR; i++) {
      if ((mode == "analyze" && i > NR - 100) || (mode == "android" && selected[i])) {
        message = message (count++ ? "\n" : "") lines[i]
      }
    }
    if (length(message) > 24000) message = substr(message, length(message) - 23999)
    if (message == "") message = "No matching diagnostics; inspect the uploaded log artifact."
    gsub(/%/, "%25", message)
    gsub(/\r/, "%0D", message)
    gsub(/\n/, "%0A", message)
    printf "::error title=%s failure diagnostics::%s\n", mode, message
  }
' "$2"
