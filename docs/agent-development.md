# Agent Development Workflow

This document operationalizes the repository instructions in [`AGENTS.md`](../AGENTS.md). It is intended for Hermes and other coding agents that work through GitHub Issues and Pull Requests.

## 1. Intake and scope

1. Fetch the complete GitHub Issue body, comments, acceptance checklist and relevant linked issues/PRs.
2. Inspect the current default branch, working tree, dependency versions, related tests and platform configuration.
3. Write a short internal task checklist. Identify prerequisites, files likely to change, migrations, tests and any required owner decision.
4. If a prerequisite is not merged, do not pretend it exists. Work on another independent issue, or use an explicitly documented stacked PR.

## 2. Implement in a focused branch

- Branch from the latest `main` unless deliberately creating a stacked PR.
- Keep one issue per PR where practical. Avoid mixing repository infrastructure, platform migration and user-facing feature work into one giant diff.
- Prefer small testable increments; preserve existing user data and compatibility.
- Add tests for the reported defect before/alongside the fix. Include negative tests for authorization and failure paths when relevant.
- Do not let the agent silently settle owner-level choices such as app identity, signing credentials, product scope, license or production database changes.

## 3. Validate and capture evidence

Run the relevant checks from `AGENTS.md`. For every command:

- Capture the command, exit code, and concise diagnostic.
- Keep logs under a temporary/build directory, not in source control, unless the log is a deliberate sanitized fixture.
- Upload reproducible CI artifacts when the workflow supports them.
- Distinguish static/code analysis from execution on a device, live backend or app-store distribution.
- If validation is blocked, state the blocking issue and continue with checks that can run independently.

CI jobs currently provide different evidence:
- Agent contract: repository guidance and workflow guardrails are present.
- Environment contract: configuration assets are reproducible and secrets are not bundled.
- Format: Dart formatting has no drift.
- Analyze: analyzer diagnostics.
- Test: test output and LCOV coverage.
- Android release: release build output and, when build succeeds, the final APK permission dump.

A failing CI job is information, not a reason to disable a gate. Fix the underlying defect or document an explicitly owner-approved temporary policy. Never make a critical quality check pass using `continue-on-error`, empty tests, or unconditional success.

## 4. Pull Request protocol

Use the repository PR template. A PR should include:

- `Closes #N` only when all required acceptance criteria are met.
- What changed and why, including the previously observable failure and expected corrected behavior.
- Exact commands run and results; identify checks not run.
- Links to CI runs/artifacts where possible.
- Schema/data migration strategy and compatibility notes.
- Security implications and remaining owner actions.

Before push: inspect the entire diff and run `git diff --check`. After push: verify the GitHub PR head/base, latest commit, CI run state and artifacts. Do not merge the PR unless explicitly instructed by the repository owner.

## 5. Safe boundaries

- Never commit `.env`, credentials, service-role keys, signing material, production records or user exports.
- Pull-request CI runs without production secrets and uses read-only token permissions.
- Database migrations must be reviewed and tested against a local/dedicated test project. Do not reset or alter production data.
- Do not label an unsigned iOS build as an installable IPA or a debug-signed Android APK as a production release.
- External credentials and account-level settings that cannot be accessed from CI must be recorded as owner prerequisites, not simulated as success.
