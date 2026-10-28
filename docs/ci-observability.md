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

- Flutter SDK is explicitly pinned to `3.47.8`; Java is explicitly pinned to 17.
- Action references in workflows use full-length commit SHAs with human-readable version comments.
- Pull-request workflows request `contents: read` only. They use `pull_request`, not `pull_request_target`, and have no production credentials.
- CI may create a temporary, non-secret `.env` fixture solely so Flutter commands can progress far enough to expose further errors while Issue #2 is open. This fixture is generated inside the ephemeral runner, is never uploaded as an artifact, and is not a valid backend configuration. It must not be used for online smoke-test claims.
- Artifact retention is 14 days to retain enough evidence for the next agent iteration without unbounded storage growth.

## Interpreting failures

The repository already has known blockers tracked by Issues #2, #4 and #5. The first workflow run also found legacy formatting drift: 59 Dart files were reported by the repository-wide formatter audit. To avoid turning a small, focused PR into an unrelated 59-file reformat, the blocking format gate checks every Dart file changed by that PR, while the complete repository audit is retained as a diagnostic artifact/warning. A dedicated formatting normalization can later make the whole-repository check blocking.

Depending on which issue has merged, runs may fail at the environment contract, the old widget test, or Android Gradle/Kotlin build. These failures are intentional signals of existing defects, not reasons to weaken the workflow. The separate jobs should still run so the project has independent diagnostics.

No live Supabase login/list query is performed by these jobs: a PR must never use production secrets or production user data. Real-network smoke tests require a dedicated test backend and a separately reviewed, secret-safe design. Likewise, successful compilation alone is not proof of 16KB page-size compatibility, signed distribution, or on-device functionality.

## Debugging a failure

1. Open the failed job and locate the first actionable error, not just the last summary line.
2. Download the corresponding artifact if the job uploaded one.
3. Reproduce locally using the pinned SDK/JDK and the command in the job.
4. Fix the cause in the issue's focused branch; do not relax unrelated checks.
5. After pushing, confirm the new workflow run uses the new head SHA and that the failure is either resolved or explicitly documented as blocked.

For deeper GitHub Actions logs, GitHub supports re-running a failed job with debug logging enabled. Do not enable verbose environment dumps that might expose credentials.
