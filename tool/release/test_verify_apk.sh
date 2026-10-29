#!/usr/bin/env bash
# Exercise the real verifier with simulated Build Tools output. No keys are used.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export ANDROID_HOME="$tmp/android" RUNNER_TEMP="$tmp"
export FIXTURE_CERT="$tmp/cert.txt" FIXTURE_BADGING="$tmp/badging.txt"
mkdir -p "$ANDROID_HOME/build-tools/36.0.0"
cat > "$ANDROID_HOME/build-tools/36.0.0/apksigner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAIL_SIGNATURE:-false}" == true ]]; then exit 1; fi
cat "$FIXTURE_CERT"
EOF
cat > "$ANDROID_HOME/build-tools/36.0.0/aapt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat "$FIXTURE_BADGING"
EOF
chmod +x "$ANDROID_HOME/build-tools/36.0.0/"{apksigner,aapt}
touch "$tmp/app.apk"
printf "package: name='com.example.belog' versionCode='42' versionName='1.2.3'\nuses-permission: name='android.permission.INTERNET'\n" > "$FIXTURE_BADGING"
expected="$(printf 'a%.0s' {1..64})"
wrong="$(printf 'b%.0s' {1..64})"
verify() {
  bash "$root/tool/release/verify_apk.sh" "$tmp/app.apk" 1.2.3 42 "$expected"
}
expect_failure() {
  local description="$1"; shift
  local output
  if output="$("$@" 2>&1)"; then
    echo "Expected failure: $description" >&2
    exit 1
  fi
  if [[ -n "$description" ]] && ! grep -Fq -- "$description" <<<"$output"; then
    echo "Missing expected failure: $description" >&2
    echo "$output" >&2
    exit 1
  fi
}

# Check the exact old and new formats, including case normalization.
printf 'Signer #1 certificate DN: CN=CI Test Only\nSigner #1 certificate SHA-256 digest: %s\n' "$expected" > "$FIXTURE_CERT"
verify >/dev/null
printf 'V2 Signer: certificate DN: CN=CI Test Only\nV2 Signer: certificate SHA-256 digest: %s\n' "${expected^^}" > "$FIXTURE_CERT"
verify >/dev/null

printf 'V2 Signer: certificate DN: CN=CI Test Only\nV2 Signer: certificate SHA-256 digest: %s\n' "$wrong" > "$FIXTURE_CERT"
expect_failure 'fingerprint does not match' verify
printf 'V2 Signer: certificate DN: C=US, O=Android, CN=Android Debug\nV2 Signer: certificate SHA-256 digest: %s\n' "$expected" > "$FIXTURE_CERT"
expect_failure 'Debug signing certificate is not allowed' verify
printf 'V2 Signer: certificate SHA-256 digest: %s\nV2 Signer: certificate SHA-256 digest: %s\n' "$expected" "$expected" > "$FIXTURE_CERT"
expect_failure 'exactly one signing certificate' verify
printf 'V2 Signer: certificate SHA-256 digest: invalid\n' > "$FIXTURE_CERT"
expect_failure 'Invalid APK certificate SHA-256 digest' verify
printf 'No certificate output\n' > "$FIXTURE_CERT"
expect_failure 'exactly one signing certificate' verify
printf 'V2 Signer: certificate DN: CN=CI Test Only\nV2 Signer: certificate SHA-256 digest: %s\n' "$expected" > "$FIXTURE_CERT"
export FAIL_SIGNATURE=true
expect_failure '' verify
unset FAIL_SIGNATURE
printf "package: name='com.example.belog' versionCode='43' versionName='1.2.3'\nuses-permission: name='android.permission.INTERNET'\n" > "$FIXTURE_BADGING"
expect_failure '' verify
printf "package: name='com.example.belog' versionCode='42' versionName='1.2.3'\n" > "$FIXTURE_BADGING"
expect_failure '' verify
echo 'APK verifier accepts both output formats and rejects invalid signatures/metadata.'
