## Related issue

Closes #

## Change summary

- 

## Why this change is needed

Describe the observable defect or missing behavior before this change and what users/developers should observe afterward.

## Validation evidence

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos`
- [ ] `flutter test --coverage`
- [ ] Relevant platform build / migration / security tests
- [ ] `git diff --check`

For each command, report **passed**, **failed**, **blocked**, or **not run**. Do not check a box without evidence. Link CI runs/artifacts when available.

## Data, migrations and compatibility

Describe any schema changes, local storage migration, rollback strategy, generated files, SDK changes or release compatibility considerations. Write “None” only after checking.

## Security and privacy

- Does this touch authentication, authorization/RLS, Storage, secrets, user data or logging?
- Confirm that no secret, `.env`, signing key, production data or sensitive logs are included.
- State any manual owner action still required.

## Observability and remaining risks

What log, error state, test, metric or artifact helps detect regressions? What has not been verified (device, live backend, app-store signing, page-size alignment, etc.)?
