# CI Validation and Observability

## Validation layers

| Workflow/check | Trigger | What it verifies | Failure evidence |
|---|---|---|---|
| Agent contract | Pull request, push to `main`, manual | Required agent docs/templates exist and CI/release workflows retain safety guardrails | Step log and GitHub annotations |
| Environment contract | Pull request, push to `main`, manual | The Flutter asset list does not bundle `.env`; no tracked `.env` is accepted | Explicit diagnostic pointing to Issue #2 |
| Dart format | Pull request, push to `main`, manual | Blocks formatting issues in changed Dart files; separately audits repository-wide formatting drift | `format-audit` artifact and formatter logs |
| Flutter analyze | Pull request, push to `main`, manual | `flutter analyze --fatal-infos` | `flutter-analyze-log` artifact (14 days) |
| Flutter tests | Pull request, push to `main`, manual | `flutter test --coverage` | `flutter-test-evidence` artifact containing test log and LCOV when produced |
| Android release | Pull request, push to `main`, manual | Release APK build and final APK `INTERNET` permission check | `android-release-evidence` artifact with build log and permission dump when available |
| Manual mobile build validation | Manually dispatched | Android release build and unsigned iOS compile check; it does not publish releases | Platform-specific build artifacts/logs; iOS output is clearly named as unsigned |

## Reproducibility

- Flutter SDK is explicitly pinned to `3.47.8`; Java is explicitly pinned to 17. Android builds use Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, and compile SDK 36. Flutter’s Android dependency validation remains enabled.
- Action references in workflows use full-length commit SHAs with human-readable version comments.
- Pull-request workflows request `contents: read` only. They use `pull_request`, not `pull_request_target`, and have no production credentials.
- CI creates a temporary, non-secret `env.json` fixture with a non-routable URL for compilation. This fixture is not a valid backend configuration and must not be used for online smoke-test claims.
- Artifact retention is 14 days to retain enough evidence for the next agent iteration without unbounded storage growth.

## CI helper scripts

The repository's CI helpers do not run in the Flutter app and do not require Python:

- `tool/ci/check_env_asset_contract.sh` checks for a tracked root `.env` and a literal `.env` entry in `pubspec.yaml`. This is a narrow configuration guard, not a general secret scanner or proof that all assets are safe.
- `tool/ci/validate_agent_contract.sh` checks that the documented agent workflow and existing CI/release guardrails are present. It is a textual guard, not a replacement for branch protection or a full YAML security audit.
- `tool/ci/annotate_failure.sh` selects bounded analyzer/Android failure excerpts for GitHub annotations; full logs remain in the existing artifacts.

CI runs `bash tool/ci/test_ci_scripts.sh` using temporary, non-secret fixtures to exercise both passing and failing cases. The scripts use Bash, Git, grep, sed, and awk on the Linux CI runner; no separate language runtime or third-party package is needed. Run the same command locally on a compatible environment when changing the helpers.

## Interpreting failures

Previous runs exposed failures tracked by Issues #4 and #5; consult the latest run rather than assuming they still apply. The first workflow run also found legacy formatting drift: 59 Dart files were reported by the repository-wide formatter audit. To avoid turning a small, focused PR into an unrelated 59-file reformat, the blocking format gate checks every Dart file changed by that PR, while the complete repository audit is retained as a diagnostic artifact/warning. A dedicated formatting normalization can later make the whole-repository check blocking.

Analyzer and Android build failures also include a bounded diagnostic excerpt in the check annotations; the full log remains available as an artifact. Failures are signals to investigate, not reasons to weaken the workflow. The separate jobs should still run so the project has independent diagnostics.

No live Supabase login/list query is performed by these jobs: a PR must never use production secrets or production user data. Real-network smoke tests require a dedicated test backend and a separately reviewed, secret-safe design. Likewise, successful compilation alone is not proof of 16KB page-size compatibility, signed distribution, or on-device functionality.

## Debugging a failure

1. Open the failed job and locate the first actionable error, not just the last summary line.
2. Download the corresponding artifact if the job uploaded one.
3. Reproduce locally using the pinned SDK/JDK and the command in the job.
4. Fix the cause in the issue's focused branch; do not relax unrelated checks.
5. After pushing, confirm the new workflow run uses the new head SHA and that the failure is either resolved or explicitly documented as blocked.

For deeper GitHub Actions logs, GitHub supports re-running a failed job with debug logging enabled. Do not enable verbose environment dumps that might expose credentials.

## Owner-side merge enforcement

The repository's `main` branch was reported as unprotected when this foundation PR was prepared. GitHub Actions can report failures, but workflows alone do not prevent a direct push or a merge when branch rules do not require the checks.

After the checks have produced stable results, the repository owner should create a branch ruleset for `main` that:

- Requires changes to arrive through a pull request rather than direct pushes.
- Requires these checks: `agent-contract / guardrails`, `config-contract / no bundled secrets`, `format / changed-Dart-format`, `analyze / flutter-analyze`, `test / flutter-test`, and `android-release / build-and-permission-check`.
- Blocks force pushes and branch deletion.
- Does not permit an administrator/agent shortcut to bypass the selected checks for ordinary changes.

Do not make these checks required while known baseline issues keep them red; resolve the underlying issues first, then enable enforcement. Repository rulesets/branch protection are server-side settings and are not changed by this PR.

GitHub recommends least-privilege workflow permissions and pinning actions to full-length commit SHAs. See [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use).
