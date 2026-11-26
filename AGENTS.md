# Agent Engineering Contract

This file is the repository-wide instruction source for coding agents. Read it before changing code. More specific `AGENTS.md` files in subdirectories, if added later, may refine these rules but must not weaken the security and delivery requirements below.

## Mission and working style

- Treat GitHub Issues as the source of task scope and acceptance criteria. Read the entire issue and relevant comments before coding; inspect current source because issue descriptions can become stale.
- Implement working software, not just plans or review prose. Prefer the smallest coherent change that completely satisfies the selected issue.
- Preserve existing behavior unless the issue explicitly changes it. Do not broaden product scope, perform unrelated cleanups, or upgrade all dependencies indiscriminately.
- Never claim a check passed unless you ran it and observed its successful exit status. Distinguish `passed`, `failed`, `blocked`, and `not run`.
- If blocked, preserve useful progress, capture the exact command and relevant diagnostic, then continue with independent work.

## Repository workflow

1. Start from a clean, up-to-date `main`. Inspect `git status --short`, `git branch --show-current`, `git log -5 --oneline`, the issue, and related PRs.
2. Never discard, overwrite, reset, or commit user-owned working-tree changes. If the tree is dirty and the ownership of a change is unclear, leave it untouched and work in a separate worktree/branch when possible.
3. Create one focused branch per issue, using `fix/issue-N-short-description`, `feat/issue-N-short-description`, or `chore/issue-N-short-description`.
4. Keep a PR focused on one issue or a small set of inseparable issues. Do not push directly to `main`, force-push shared branches, or merge PRs unless the repository owner explicitly instructs you to do so.
5. Before committing, inspect `git diff --check`, `git diff --stat`, and the complete diff. Remove credentials, generated noise, unrelated formatting and accidental files.
6. Push the branch and open a PR against `main`. Include the issue reference, implementation summary, validation evidence, risks, data migration notes and unresolved blockers. Use `Closes #N` only when the complete issue acceptance criteria are met.
7. After pushing, verify that the PR exists, points at the intended branch, and that its workflow runs started. Do not equate “PR created” with “issue fixed”.
8. Issues may keep a `[P1][area]` title prefix, but they must also carry the matching `P0`–`P3` priority label and a category label (`bug`, `tech-debt`, `cleanup`, `ui-consistency`, `ci`, `tests`, `documentation`, `security`, `process`). New issues start from `.github/ISSUE_TEMPLATE/`; Dependabot PRs are labelled `dependencies`.

## Commands and evidence

Use the versions declared by the repository/CI rather than silently following the latest SDK. The CI currently pins Flutter `3.47.8` (recorded in `tool/flutter_version.txt`) and Java `17`; toolchain upgrades must be explicit and tested as a compatible set. Local debug scripts intentionally warn instead of blocking on Flutter drift when the Dart SDK still satisfies `pubspec.yaml`; release packaging and CI require the pin exactly, so do not weaken those checks.

Run the applicable checks before opening or updating a PR:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed path/to/each/changed_file.dart
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --release
```

The only generated code left is the ARB localization class, produced by `flutter gen-l10n` (driven by `l10n.yaml` and `generate: true`) whenever the app builds or tests run; the former Isar schemas and their `build_runner` step were removed with the Isar dependency (#107), so no `build_runner` invocation is part of the workflow any more (the dev dependency itself was dropped in the 2026-11 audit: there is no builder to run and no `part '*.g.dart'` file in `lib/`). Only run commands supported by the current dependency/toolchain; explain any unavailable command.

- In a focused PR, at minimum format-check every changed Dart file. The CI also audits repository-wide formatter drift as a diagnostic artifact; do not mass-reformat unrelated files just to make an unrelated feature PR pass.
- Record each command and its actual result in the PR description.
- If a command fails, preserve the diagnostic output and fix the cause where it is in scope. Do not delete tests, weaken assertions, globally suppress lints, or use `continue-on-error` to manufacture green checks.
- Do not report runtime, real-device, production backend, 16KB page-size, signing, or deep-link validation as completed unless that exact validation was actually executed.
- Coverage is evidence, not a vanity number. Do not reduce assertions or add meaningless tests to improve the percentage.
- CI fails when line coverage drops below the floor in `tool/ci/coverage_threshold.json` (`python3 tool/ci/check_coverage.py`). Raise the floor deliberately when coverage has grown; never lower it to make a PR pass.

## Secrets, configuration and external services

- Never commit `.env`, private keys, signing keystores, access tokens, service-role/secret keys, production credentials, or real user data.
- Client-side backend configuration is a single public `API_BASE_URL` origin (no client key is embedded). Authorization is enforced per request by the no-wave backend; the app must never embed administrative credentials.
- Do not print secrets, environment dumps, full auth/session objects, or sensitive user data in terminal logs, CI artifacts, screenshots or PR comments.
- The app has no telemetry or automatic reporting. In-app diagnostics stay in a bounded in-memory buffer; they leave the device only when the user explicitly copies, shares or exports them from the diagnostics dialog (the exported log file is redacted and handed to the system share sheet, never uploaded by the app).
- Pull-request CI must not need production secrets. Do not introduce `pull_request_target` or execute untrusted PR code with privileged tokens.
- Use a fake, non-routable placeholder only when a build tool requires a local configuration file; document that it is a CI fixture and never use it to claim backend smoke tests passed.
- Never mutate, reset, truncate, migrate destructively, or upload test content to the production backend. Validate migrations in a local or dedicated test deployment.
- Treat production-schema details and security policies as unknown until confirmed from repository migrations or an authorized, read-only inspection.

## Data, architecture and generated files

- Keep domain logic independent of persistence and UI frameworks where the current architecture permits. Do not put database annotations, SDK response types, or widget state in domain entities without a documented reason.
- Any schema or persistence change must consider existing user data, migration/rollback behavior and tests. Never clear local drafts or preferences as a shortcut.
- Preserve generated files that belong to committed generators; regenerate them using the repository's configured toolchain instead of hand-editing generated output.
- Async writes must be awaited. Define stable ordering and identifiers for pagination, caches and relationships. Make offline behavior explicit instead of reporting a fake success.
- Protect authorization at the trusted server/database layer; hiding a client button is not authorization.
- Any address the server controls reaches the operating system through one door: `ArticleResourceOpener.open(value)` (`lib/core/utils/article_resource_opener.dart`). The door applies the whitelist (`resolveArticleResourceUrl` / `isValidArticleResourceUrl` in `lib/core/utils/article_resource_url.dart`: http(s) only, no embedded credentials, and a site-relative value resolved against a configured `WEB_BASE_URL` rather than guessed from the API origin), picks the launch mode, and answers `rejected` / `unavailable` / `opened` so a page says the right thing in each case. A widget asks `accepts(value)` rather than resolving on its own, so the inert/tappable decision and the launch cannot drift apart; a rejected value stays readable but gets no handler. `lib/` may contain exactly one `launchUrl(` call site - the door - and `test/unit/core/external_link_guard_test.dart` fails the suite otherwise, allowlisting only the about page, whose `mailto:` and repository links are compiled-in constants rather than server data (#369). Both knobs exist so a test can count what would have left the app.
- Dependency registrations live in one module per feature under `lib/di/` (listed in `lib/di/app_modules.dart`); `lib/init_dependencies.dart` is only the composition root (storage, session, HTTP client) and must stay at or under 150 lines (#304). A new registration needs a row in `test/unit/di/app_modules_test.dart`, which resolves every registered type from the real modules.
- Configured values have one home (#295): a timeout, debounce, dwell time, retry schedule or retention window is a named constant in `lib/core/config/app_durations.dart`; a page size or row cap lives in `lib/core/config/app_limits.dart`; a route pattern or navigation location lives in `lib/router/route_paths.dart`. Call sites read the constant. `test/unit/design/no_magic_durations_test.dart` and `test/unit/core/route_paths_guard_test.dart` reject new literals elsewhere; animation durations still come from `NoWaveMotion`.

## UI and design system

- Read `docs/design-system.md` before adding or changing a widget. It is the catalogue of tokens, shared components and the closed list of when a raw Material widget is allowed. Reuse an existing `NoWave*` component or theme token instead of inventing a parallel one: a fifth button style is a design decision, not a local one.
- A new or changed component or token must land with its catalogue row and a test. `test/unit/core/docs_contract_test.dart` fails when something under `lib/core/design/components` is not in the table or a token in `design_tokens.dart` is undocumented, so the catalogue cannot quietly fall behind the code.
- The numeric and component rules are gates, not advice: `test/unit/design/no_magic_numbers_test.dart` (spacing literals, ceiling 0), `test/unit/design/no_magic_radius_and_type_test.dart`, `test/unit/design/design_tokens_test.dart` and `test/unit/design/component_usage_guard_test.dart` (a per-file budget freezing `ElevatedButton`/`FilledButton`/`TextButton`/`OutlinedButton`/`AlertDialog` in `lib/features`). Never raise a ceiling or widen a budget to make a PR pass; when you migrate a call site, lower or delete its budget line in the same commit. A one-off number is marked on its own line with `// design-token-ok: <reason>`, where a reviewer cannot miss it.
- A UI change carries evidence for the states a diff cannot show: light and dark theme, a 320dp-wide layout, the largest text scale, and the busy/disabled labels. A widget test that asserts those (the `test/widget/no_wave_*_test.dart` files, `test/widget/persona_sweep.dart`) counts as that evidence; a screenshot of one state does not. If a screen is genuinely unaffected, say why rather than leaving the box empty.
- There is no golden or pixel gate, so a deliberate visual deviation must be written down twice: the reason in the PR description and a comment at the call site, because the code will otherwise look like it broke the rule.

## Completion report

Every PR or work report must state:

- Issue(s) and scope.
- Changed files and observable behavior.
- Commands run with pass/fail/blocked/not-run status.
- CI run and artifact links when available.
- Security, migration, compatibility and performance implications.
- Remaining blockers and the exact evidence needed to remove them.

Do not close an issue just because code was committed. Close it only after the acceptance criteria are met.
