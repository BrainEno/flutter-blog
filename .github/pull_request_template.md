## Related issue

Closes #

## Change summary

- Describe the intended change.

## Why this change is needed

Describe the observable defect or missing behavior before this change and what users/developers should observe afterward.

## Validation evidence

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos`
- [ ] `flutter test --coverage`
- [ ] Relevant platform build / migration / security tests
- [ ] `git diff --check`

For each command, report **passed**, **failed**, **blocked**, or **not run**. Do not check a box without evidence. Link CI runs/artifacts when available.

## UI evidence

Required for any PR that changes a widget, layout, theme or user-visible copy; otherwise write "Not applicable" and why.

- [ ] Read `docs/design-system.md` and reused an existing `NoWave*` component or token, or the departure is justified below.
- [ ] New or changed component/token has a catalogue row in `docs/design-system.md` and a test.
- [ ] Light and dark theme, 320dp width and the largest text scale covered - name the widget test that asserts them, or state why the change cannot affect them.
- [ ] No new spacing/radius/type literals and no new raw Material action component: `test/unit/design/` budgets only shrink in this PR.
- [ ] Visual deviations and their reasons written into this description, not only into the code.

## Data, migrations and compatibility

Describe any schema changes, local storage migration, rollback strategy, generated files, SDK changes or release compatibility considerations. Write “None” only after checking.

## Security and privacy

- Does this touch authentication, authorization/RLS, Storage, secrets, user data or logging?
- Confirm that no secret, `.env`, signing key, production data or sensitive logs are included.
- State any manual owner action still required.

## Observability and remaining risks

What log, error state, test, metric or artifact helps detect regressions? What has not been verified (device, live backend, app-store signing, page-size alignment, etc.)?
