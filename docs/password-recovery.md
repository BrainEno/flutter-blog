# Password recovery in the Flutter app

The App uses no-wave's anonymous identity endpoints:

| Action | Request | Success |
| --- | --- | --- |
| Request a link | `POST /auth/forgot-password` with `{email}` | `202 {data:{ok:true}}` |
| Set a new password | `POST /auth/reset-password` with `{token,password}` | `200 {data:{ok:true}}` |

The recovery endpoint answers the same way for registered and unregistered addresses. The App never says whether an account exists. A `MAIL_DISABLED` response is not success: the UI shows **「暂不提供」** and does not keep retrying an instance whose mail switch is off. Older API deployments that return 404/405 are reported as unsupported.

## Mail and the reset link

`MAIL_ENABLED` is off by default. The API returns `409 MAIL_DISABLED` before spending a rate-limit attempt or issuing a token while mail is disabled. Turning the switch on is not, by itself, proof of delivery: a configured SMTP relay and sender are required. Without SMTP configuration the upstream API uses its log mailer, which does not include the reset link in logs by default. A successful `202` therefore means the API accepted the request, not that an e-mail reached an inbox.

The e-mail URL points to the web app's `/reset-password?token=…` page; it is not an App deep link. From the App, open **Forgot password → I already have a reset link**, then paste either the complete URL or the 43-character token. The client extracts only the token and sends it in the JSON body. Existing article deep-link parsing is unchanged.

The App's success copy is deliberately generic and notes that delivery is not confirmed. If the response is lost, it tells the reader to check the inbox before trying again because issuing another link supersedes the previous one.

## One-time token and password rules

- The token is 32 random bytes encoded as unpadded base64url: exactly 43 characters. The App refuses malformed pastes locally so they do not spend a server attempt.
- A reset token lasts 30 minutes and is single-use. A rejected token is described only as invalid, expired, or already used.
- The new password uses the registration rules: 12–128 Unicode code points and at most 512 UTF-8 bytes. Passwords are not trimmed; leading and trailing spaces remain part of the credential. The form also requires a matching confirmation.
- A successful reset changes the password and revokes every session for that account. The App does not silently sign in again; it asks the reader to sign in with the new password.
- A timeout, 5xx, or malformed success response may arrive after the server committed the reset. The App does not retry the token and tells the reader to try the new password at sign-in first; if that fails, request a fresh link.

Both requests are sent without a bearer token, redirects, or automatic 401 replay. The email, token, and password are not persisted or logged; reset credentials are cleared from the form as the request starts. Server error messages are not rendered directly.

## Implementation and verification boundary

- Domain contract, token extraction, and UI-facing use cases: `lib/features/auth/domain/password_recovery.dart`, `domain/repository/password_recovery_repository.dart`, and `domain/usecases/{request_password_reset,reset_password}.dart`.
- API and error mapping: `lib/features/auth/data/repositories/password_recovery_repository_impl.dart`.
- Screens and entry point: `presentation/pages/password_recovery_page.dart`, `password_reset_page.dart`, and the login page.
- Contract tests: `test/unit/auth/password_recovery_repository_test.dart`; UI and routing tests: `test/widget/password_recovery_pages_test.dart` and `router_test.dart`.

Tests pin anonymous request shape, one-time token handling, non-replay behavior, generic outcomes, and failure states. They do not prove that a deployment has `MAIL_ENABLED`, SMTP credentials, a verified sender, or successful real-world delivery. Production mail configuration and delivery remain **unverified**; the real-device matrix also remains **unverified**.
