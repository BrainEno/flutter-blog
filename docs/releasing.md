# Release and signing policy

## Identity and compatibility (owner decision required)

The current Android application ID is `com.example.belog`; the iOS Runner bundle ID is `com.nodeman24.belog`. They are intentionally unchanged. The proposed canonical ID is `com.nodeman24.belog`, matching iOS, but the owner must approve it and a migration plan before any ID change. Changing Android's ID creates a separate app and will not upgrade existing installations or retain their private data automatically. Changing an existing signing certificate can also prevent upgrades unless the applicable store's signing-key rotation process is used. We do not know whether either ID has shipped or who owns its signing keys.

Until the owner resolves this, the release workflow refuses to publish unless the protected `production` environment explicitly sets `ANDROID_APPLICATION_ID_APPROVED` to the **current** ID, `com.example.belog`. Approval does not mean the example ID is suitable for a store. An ID migration requires changing the application, this gate, and release documentation together; do not silently rename it.

## Validation builds are not releases

PR CI and the manual workflow set `BELOG_QA_BUILD=true` explicitly, compile with the debug key and a non-routable Supabase fixture, and label their APK `belog-QA-debug-signed.apk`. They are not production packages and cannot test backend connectivity. iOS validation creates an unsigned `.zip`, never an `.ipa`. These workflows do not publish. `flutter build apk --release` fails without signing credentials by default. To reproduce only the QA build locally, use `BELOG_QA_BUILD=true flutter build apk --release --dart-define-from-file=env.json`; never distribute that APK.

## Production Android release

The separate tag workflow is the only publishing path. Configure a protected GitHub environment named `production` with required reviewers and restricted tag creation/updates before using it. Store the following **environment** values (do not commit them or put them in logs):

- Variables: `ANDROID_APPLICATION_ID_APPROVED` (see above), `ANDROID_RELEASE_CERT_SHA256` (64 hexadecimal digits, no colons, for the approved signing certificate), and `SUPABASE_URL` (real HTTPS endpoint).
- Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, and `SUPABASE_PUBLISHABLE_KEY` (only the public publishable key or legacy anon JWT, never a secret or service-role key). The public key is embedded in the APK; authorization must be enforced by Supabase RLS and Storage policies. Key shape checks do not prove backend security.

Use the correct existing production signing key if users already have the app. Back up and restrict it under the owner's control; loss or replacement can break upgrades. Obtain the expected SHA-256 fingerprint independently, for example using `keytool -list -v` on the approved keystore, and verify it out of band. The workflow rejects missing credentials, the standard debug alias/certificate, a fingerprint mismatch, unapproved app ID, mismatched package/version/permission, placeholder backend URL, and secret-key formats. Temporary files are removed after the job; GitHub runner and environment security remain owner responsibilities.

Set `version: MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`, with a positive Android version code no greater than 2100000000. Merge and validate that commit on `main`. Create a new immutable tag exactly `vMAJOR.MINOR.PATCH+BUILD` pointing to a commit reachable from `main`; only tag pushes trigger publication. The workflow uses the matching values as Flutter build name and number, checks the resulting APK metadata and signature, then creates a new GitHub Release with generated notes and a versioned APK name. It fails rather than replacing an existing release or asset. Never move/reuse release tags. The current `0.0.0+1` is a placeholder, not a recommendation for a first release.

A successful CI fixture-signing test does not validate production credentials, store acceptance, device installation, backend configuration, or real signing. No production signing or publication has been performed by this change. There is no iOS publishing workflow: an installable IPA requires a separately reviewed certificate, provisioning profile, distribution method and signed build. Do not rename the unsigned validation zip to `.ipa`.
