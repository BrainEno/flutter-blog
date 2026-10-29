#!/usr/bin/env bash
# Parse exactly one SHA-256 certificate fingerprint from apksigner output.
# Build Tools have used both "Signer #1 certificate ..." and
# "V2 Signer: certificate ..." prefixes; match the field name, not its prefix.
read_apk_signer_sha256() {
    local output_file="$1" count fingerprint
    count="$(awk 'index($0, "certificate SHA-256 digest:") { n++ } END { print n+0 }' "$output_file")"
    if [[ "$count" != 1 ]]; then
        echo 'APK must have exactly one signing certificate.' >&2
        return 1
    fi
    fingerprint="$(awk '
      index($0, "certificate SHA-256 digest:") {
        sub(/^.*certificate SHA-256 digest:[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        print
      }
    ' "$output_file")"
    if [[ ! "$fingerprint" =~ ^[[:xdigit:]]{64}$ ]]; then
        echo 'Invalid APK certificate SHA-256 digest in apksigner output.' >&2
        return 1
    fi
    printf '%s\n' "${fingerprint,,}"
}
