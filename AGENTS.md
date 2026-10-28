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

## Commands and evidence

Use the versions declared by the repository/CI rather than silently following the latest SDK. The CI currently pins Flutter `3.47.8` and Java `17`; toolchain upgrades must be explicit and tested as a compatible set.

Run the applicable checks before opening or updating a PR:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed path/to/each/changed_file.dart
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --release
```

For generated code, also run the generator used by the current dependency set, for example `dart run build_runner build --delete-conflicting-outputs`. Only run commands supported by the current dependency/toolchain; explain any unavailable command.

- In a focused PR, at minimum format-check every changed Dart file. The CI also audits repository-wide formatter drift as a diagnostic artifact; do not mass-reformat unrelated files just to make an unrelated feature PR pass.
- Record each command and its actual result in the PR description.
- If a command fails, preserve the diagnostic output and fix the cause where it is in scope. Do not delete tests, weaken assertions, globally suppress lints, or use `continue-on-error` to manufacture green checks.
- Do not report runtime, real-device, production backend, 16KB page-size, signing, or deep-link validation as completed unless that exact validation was actually executed.
- Coverage is evidence, not a vanity number. Do not reduce assertions or add meaningless tests to improve the percentage.

## Secrets, configuration and external services

- Never commit `.env`, private keys, signing keystores, access tokens, service-role/secret keys, production credentials, or real user data.
- Client-side Supabase configuration may contain a public anon/publishable key only. The app must never use a Supabase `service_role` or secret key. Client security depends on server-side RLS and Storage policies.
- Do not print secrets, environment dumps, full auth/session objects, or sensitive user data in terminal logs, CI artifacts, screenshots or PR comments.
- Pull-request CI must not need production secrets. Do not introduce `pull_request_target` or execute untrusted PR code with privileged tokens.
- Use a fake, non-routable placeholder only when a build tool requires a local configuration file; document that it is a CI fixture and never use it to claim backend smoke tests passed.
- Never mutate, reset, truncate, migrate destructively, or upload test content to the production Supabase project. Validate migrations in a local or dedicated test project.
- Treat production-schema details and security policies as unknown until confirmed from repository migrations or an authorized, read-only inspection.

## Data, architecture and generated files

- Keep domain logic independent of persistence and UI frameworks where the current architecture permits. Do not put database annotations, SDK response types, or widget state in domain entities without a documented reason.
- Any schema or persistence change must consider existing user data, migration/rollback behavior and tests. Never clear local drafts or preferences as a shortcut.
- Preserve generated files that belong to committed generators; regenerate them using the repository's configured toolchain instead of hand-editing generated output.
- Async writes must be awaited. Define stable ordering and identifiers for pagination, caches and relationships. Make offline behavior explicit instead of reporting a fake success.
- Protect authorization at the trusted server/database layer; hiding a client button is not authorization.

## Completion report

Every PR or work report must state:

- Issue(s) and scope.
- Changed files and observable behavior.
- Commands run with pass/fail/blocked/not-run status.
- CI run and artifact links when available.
- Security, migration, compatibility and performance implications.
- Remaining blockers and the exact evidence needed to remove them.

Do not close an issue just because code was committed. Close it only after the acceptance criteria are met.
