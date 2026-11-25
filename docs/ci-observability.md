# CI Validation and Observability

> 状态：active ｜ 最后核对：2026-11-25 @ facf5ad

## Validation layers

| Workflow/check | Trigger | What it verifies | Failure evidence |
|---|---|---|---|
| Agent contract | Pull request, push to `main`, manual | Required agent docs/templates exist and CI/release workflows retain safety guardrails | Step log and GitHub annotations |
| Environment contract | Pull request, push to `main`, manual | The Flutter asset list does not bundle `.env`; no tracked `.env` is accepted | Explicit diagnostic pointing to Issue #2 |
| Dart format | Pull request, push to `main`, manual | Blocks formatting issues in changed Dart files; separately audits repository-wide formatting drift | `format-audit` artifact and formatter logs |
| Flutter analyze | Pull request, push to `main`, manual | `flutter analyze --fatal-infos` | `flutter-analyze-log` artifact (14 days) |
| Flutter tests | Pull request, push to `main`, manual | `flutter test --coverage` | `flutter-test-evidence` artifact containing test log and LCOV when produced |
| Coverage floor | Pull request, push to `main`, manual | `tool/ci/check_coverage.py` compares LCOV line coverage (generated localizations excluded) with `tool/ci/coverage_threshold.json` | `Line coverage` notice or `Coverage below floor` error annotation, the least-covered files in the job summary, and the same LCOV artifact |
| Android release | Pull request, push to `main`, manual | Explicitly debug-signed QA release build, APK permission and alignment checks, isolated signing guard tests, debug build and debug/release cleartext policy | `android-release-evidence` includes build, signing, `apk-asset-audit.log`, `android-debug-check.log` and `gradle-worker-check.log` plus manifest dumps when available |
| Read-aloud desktop compile | Pull request, push to `main`, manual | macOS and Windows debug native compiles for the read-aloud desktop runners | `read-aloud-<target>-compile-log` artifact (14 days), bounded annotation on failure, cancellation note in the job summary |
| Local scripts and iOS build | Pull request, push to `main`, manual | Shell and PowerShell mock control flow, iOS simulator compile, ad-hoc IPA script run, debug/release network policy | Job log plus a bounded annotation from `tool/ci/annotate_failure.sh`; this workflow uploads no artifact, so build logs are not retained |
| Manual mobile build validation | PR, or manually dispatched | Android QA release build and optionally unsigned iOS compile; it does not publish releases | Platform-specific build artifacts/logs; iOS output is clearly named as unsigned |
| Build personal mobile packages | Relevant PR changes, or manually dispatched on `main` | PR: disposable Android signing key and unreachable API fixture, plus device IPA packaging. Manual: configured public API, iOS AltStore input and/or Android owner-signed or explicitly debug APK | PR fixture logs only; manual artifacts include binaries, SHA-256 and provenance; see [mobile-packages.md](mobile-packages.md) |

## Reproducibility

- Flutter SDK is explicitly pinned to `3.47.8` in `tool/flutter_version.txt`; every workflow must use that value (enforced by `scripts/tests/test_flutter_pin.py`), while local debug scripts warn on drift and release packaging requires the exact version. Java is explicitly pinned to 17. Android builds use Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, and compile SDK 36. Flutter’s Android dependency validation remains enabled.
- Action references in workflows use full-length commit SHAs with human-readable version comments.
- Pull-request workflows request `contents: read` only. They use `pull_request`, not `pull_request_target`, and have no production credentials.
- CI creates a temporary, non-secret `env.json` fixture with a non-routable URL for compilation. This fixture is not a valid backend configuration and must not be used for online smoke-test claims.
- Diagnostic artifacts are generally retained for 14 days; manually requested personal mobile packages are retained for 30 days, subject to repository/organization limits.

## CI helper scripts

The repository's CI helpers do not run in the Flutter app and do not require Python:

- `tool/ci/check_env_asset_contract.sh` checks for a tracked root `.env` and a literal `.env` entry in `pubspec.yaml`. This is a narrow configuration guard, not a general secret scanner or proof that all assets are safe.
- `tool/ci/validate_agent_contract.sh` checks that the documented agent workflow and existing CI/release guardrails are present. It is a textual guard, not a replacement for branch protection or a full YAML security audit.
- `tool/ci/annotate_failure.sh` selects bounded analyzer/Android failure excerpts for GitHub annotations; full logs remain in the existing artifacts.
- `tool/ci/setup_android_gradle.sh` creates a private, fresh Gradle user home for the main Android CI job and limits it to one worker. This bounds concurrent transformations, does not change developer Gradle settings or other workflows, and can make CI slower.
- `tool/ci/summarize_cancellation.sh` turns a cancelled job into a run-summary note that says the job was cancelled rather than failed, with the two follow-up paths (superseded by a newer commit, or re-run once and file an infrastructure report). It is called from the macOS and Windows jobs under `if: cancelled()`.
- `tool/ci/check_coverage.py` (standard-library Python, tested by `tool/ci/test_check_coverage.py`) merges repeated LCOV records per file, applies the exclusion globs and fails below the configured floor. The floor is a ratchet against silent regressions: raise it in a reviewed PR when coverage grows, never lower it to pass an unrelated change.
- `tool/ci/check_android_debug.sh` verifies Gradle reports one worker, stops the previous Gradle daemon and compiles the debug APK with a fresh Gradle heap. It then checks that only debug opts into development cleartext traffic. CI captures output with the non-secret fixture; mocks cover configuration, worker/daemon failures, missing output, failed builds and both policy violations.

CI runs `bash tool/ci/test_ci_scripts.sh` using temporary, non-secret fixtures to exercise both passing and failing cases. These helpers use Bash, Git, grep, sed, and awk on the Linux CI runner; no separate language runtime or third-party package is needed. Run the same command locally on a compatible environment when changing the helpers.

The production release validator (`tool/release/validate_release.py`) and its tests still use Python's standard library. They validate release versions, key types, public IP/URL restrictions and signing configuration, and write a private JSON fixture without exposing secrets. Replacing that security-sensitive parsing without equivalent negative tests could weaken release safeguards; Python is retained for this separate production workflow.

## Cancellation and job ceilings

Three workflows verify a commit that has landed on `main`: `ci.yml`,
`read-aloud-desktop.yml` and `local-scripts.yml`. Each of them cancelled
in-progress runs unconditionally within the ref, so a second merge into `main`
cancelled the run the first merge had just earned: the commit that CI exists to
judge was never judged. A check that cancels its own evidence is not a green or
red signal, it is the absence of one, which is how a healthy merge started
looking like a red `main`.

Those workflows now cancel only `pull_request` runs, where a newer commit really
does supersede an older one:

    concurrency:
      group: <workflow>-${{ github.ref }}
      cancel-in-progress: ${{ github.event_name == 'pull_request' }}

- `push` and `workflow_dispatch` runs on `main` always finish, so a `main` result
  describes that commit even when two merges land back to back. Queued `main`
  runs cost Actions minutes; that is the price of keeping the signal.
- Every job on that path declares `timeout-minutes`, set well above observed
  durations. The ceiling exists to bound a wedged runner, not to trim a slow but
  healthy job.
- A job that builds on a macOS or Windows runner ends with
  `tool/ci/summarize_cancellation.sh` under `if: cancelled()`. GitHub renders a
  cancelled job and a failed one as the same red cross, and the two answers send
  a contributor in opposite directions; the step writes the distinction into the
  run summary. A hard runner loss still bypasses every step, which is why the
  timeout is the backstop rather than the summary step.
- `tool/ci/validate_agent_contract.sh` enforces all three rules for every
  workflow that triggers on `push` to `main`, so a workflow added later inherits
  them instead of rediscovering them.

`release.yml` and the Android job of `dart.yml` keep unbounded publish/compile
jobs on purpose for now: aborting a release that overruns a guessed ceiling is a
worse failure than a slow manual job, and picking that number needs the owner's
data on real release durations. It is a recorded exception, not an oversight.

## Interpreting failures

Previous runs exposed failures tracked by Issues #4 and #5; consult the latest run rather than assuming they still apply. The first workflow run also found legacy formatting drift: 59 Dart files were reported by the repository-wide formatter audit. To avoid turning a small, focused PR into an unrelated 59-file reformat, the blocking format gate checks every Dart file changed by that PR, while the complete repository audit is retained as a diagnostic artifact/warning. A dedicated formatting normalization can later make the whole-repository check blocking.

Analyzer and Android build failures also include a bounded diagnostic excerpt in the check annotations; the full log remains available as an artifact. Failures are signals to investigate, not reasons to weaken the workflow. The separate jobs should still run so the project has independent diagnostics.

For example, [main run 41304337840](https://github.com/BrainEno/flutter-blog/actions/runs/41304337840) failed during debug `JetifyTransform` with `Java heap space` after release/signing succeeded. The CI-only worker limit and fresh Gradle daemon mitigate resource contention without skipping the check or disabling Jetifier; one successful run does not guarantee OOM can never recur. The earlier [PR run 41297353518](https://github.com/BrainEno/flutter-blog/actions/runs/41297353518) failed at the same step but its detailed log was unavailable, so its cause is not established.

Standard CI APKs are debug-signed QA artifacts; the personal-package PR check instead uses a disposable signing key. Neither is an owner-signed release. See [release policy](releasing.md) for the separate signed tag workflow.

No live no-wave login/list query is performed by these jobs: a PR must never use production secrets or production user data. Real-network smoke tests require a dedicated test backend and a separately reviewed, secret-safe design. Android jobs explicitly check APK ZIP/native-library 16 KiB alignment; compilation alone would not establish it, nor does it prove installation or on-device functionality.

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

## 工作流一览（原 README，#298）

`.github/workflows/ci.yml`（PR / push 到 main 时运行，Flutter 3.47.8 + JDK 17）：

1. **format**：对本次改动的 `.dart` 文件强制 `dart format` 通过
   （全仓库格式审计仅告警，不阻断）。
2. **analyze**：`flutter analyze --fatal-infos`，零告警门禁（`avoid_print`
   已启用，请使用 `AppLogger`）。
3. **test**：`flutter test --coverage --concurrency=1`，随后
   `python3 tool/ci/check_coverage.py` 按 `tool/ci/coverage_threshold.json` 的最低行覆盖率
   门禁（排除生成的本地化类）；覆盖率增长后再有意上调，不得为通过 PR 而下调。
4. **android-release**：使用显式 QA debug 签名和不可路由配置构建 Android release APK，
   另编译 debug APK 并检查两者网络策略；不发布、不代表正式签名已验证。

`.github/workflows/local-scripts.yml` 在 Linux/macOS/Windows 上运行本地脚本的
mock 控制流测试，并在 macOS 上编译 iOS debug 模拟器版本、运行默认 ad-hoc IPA
脚本及检查 debug/release 网络策略。`.github/workflows/dart.yml` 的额外 iOS
无签名编译只在手动选择 `include_ios` 时执行。CI 编译/打包不等同于真实模拟器
启动、设备安装、后端或分发签名实测。

单元与 widget 测试覆盖：分页/刷新竞态（BlogBloc）、搜索竞态（BlogSearchBloc）、
点赞并发与回滚、草稿隔离与自动保存、异常映射矩阵、离线行为、API 客户端
envelope/401 刷新重放、会话刷新单飞、contentBlocks 编解码、Markdown 渲染
（结构/样式/原始 HTML 惰性/javascript: 链接不可点）、阅读历史（去重/排序/
按账号隔离/清空/v2→v3 升级）、导出文档形状、分享 URL 构造等。
