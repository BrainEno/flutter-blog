# Release and signing policy

## Identity, license and version

The owner fixed the release identity in November 2026 (#109):

- Every platform uses the bundle/application ID `com.nodeman24.nowave`: Android
  `namespace` and `applicationId` in `android/app/build.gradle`, the Kotlin
  package of `MainActivity`, and `PRODUCT_BUNDLE_IDENTIFIER` in the iOS and
  macOS projects. The Windows resource metadata uses `com.nodeman24`.
- `pubspec.yaml` carries `0.2.0+1`. Release tags must be exactly
  `v0.2.0+1` (see below); the workflow passes that name and build number to
  Flutter, so the version is injected by the toolchain rather than edited per
  release.
- The project is licensed under the Apache License, Version 2.0 (`LICENSE`).
  Bundled fonts and other third-party material are listed in `NOTICE`, with the
  full OFL texts shipped next to the fonts.
- `test/unit/core/release_identity_test.dart` fails the suite when the version,
  the three platform identifiers, or the license files drift apart.

### Upgrading from the previous identifier

The previous ids were `com.example.belog` (Android) and `com.nodeman24.belog`
(iOS/macOS). A different application ID is a **different app**: a store cannot
upgrade an existing installation, and the old app keeps its own private storage
(`belog.sqlite` with drafts, reading history and cached articles, plus the
theme/language preferences) and its own keychain-backed session.

No store build was ever published under the old ids, so this rename is not an
end-user migration. Anyone holding an older local QA or personal build should:

1. Export what matters from the old install before removing it: the app's data
   export writes a JSON file (`导出我的数据`), and unattributed legacy drafts can
   be extracted from a copy of the database with
   `tool/export_unclaimed_drafts.py` (see [unclaimed-drafts.md](unclaimed-drafts.md)).
2. Install the new package and sign in again: the new id starts with no stored
   session.
3. Do not uninstall the old app until the export has been verified; uninstalling
   deletes its private storage.

If an identifier with real users ever ships, further changes need this analysis
plus the store's signing-key rotation process.

## Release gate

The publishing workflow refuses to publish unless the protected `production`
environment explicitly approves the identity it is about to build:
`ANDROID_APPLICATION_ID_APPROVED` must equal `com.nodeman24.nowave`, the value
the code is compiled with - `tool/release/validate_release.py` compares both, so
a rename that misses one side fails closed. Approval does not mean any
identifier is suitable for a store; changing the id again requires changing the
application, this gate, and this document together.

## Validation builds are not releases

PR CI and the mobile validation workflow set `BELOG_QA_BUILD=true` explicitly, compile with the debug key and a non-routable API base URL fixture, and label their APK `belog-QA-debug-signed.apk`. They are not production packages and cannot test backend connectivity. PR iOS CI also exercises ad-hoc IPA packaging with an unreachable fixture; the separate optional unsigned check produces a `.zip`. Neither is a usable personal build. `flutter build apk --release` fails without signing credentials by default. To reproduce only the QA build locally, use `BELOG_QA_BUILD=true flutter build apk --release --dart-define-from-file=env.json`; never distribute that APK.

For owner-requested, downloadable AltStore IPA or Android APK builds without creating a tag, see [mobile-packages.md](mobile-packages.md). That manual Actions workflow separates iOS from Android signing, requires a public backend configuration, labels temporary debug APKs, and never publishes a GitHub Release.

## Bundled asset and size audit

Every Android release build (PR CI and the validation workflow) runs
`tool/ci/check_apk_assets.py` over the built APK and attaches
`apk-asset-audit.log` to the build evidence. The audit answers the only
questions that matter for bundle hygiene, from the artifact rather than from
memory:

- **Is every bundled asset declared?** A file under
  `assets/flutter_assets/assets/` that `pubspec.yaml` does not declare means the
  build and the manifest disagree.
- **Is every bundled asset referenced?** The scan looks for the path or the
  file name in `lib/**/*.dart` and in the manifest *outside* the `assets:` list,
  so `fonts:` and `flutter_launcher_icons:` count as usage while "it is inside a
  declared directory" does not. This is what would have caught the ~1.1 MiB
  image that motivated issue #109. Font license texts (`OFL-*.txt`) are
  expected to have no code reference and are exempt, because the OFL requires
  shipping them.
- **Is it inside the budget?** One asset above 1 MiB
  (`--budget-bytes`) fails the job: a near-megabyte asset has to be a
  deliberate decision, not an accident.

The log also breaks the APK down by bucket (`lib/<abi>`, `dex`, `res/`,
declared assets, engine assets, signature) and lists the largest entries, so
size questions are answered by the current build. Debug-signed QA APKs and the
signed release APK are built from the same manifest, so the audit is meaningful
on both; the signing key and the API base URL are the only differences.

The checks are unit-tested (`tool/ci/test_check_apk_assets.py`, run by
`config-contract`) against synthetic APKs, including the vacuous-pass case: an
APK with no bundled assets fails instead of reporting success.

## Production Android release

The separate tag workflow is the only publishing path. Configure a protected GitHub environment named `production` with required reviewers and restricted tag creation/updates before using it. Store the following **environment** values (do not commit them or put them in logs):

- Variables: `ANDROID_APPLICATION_ID_APPROVED` (see above), `ANDROID_RELEASE_CERT_SHA256` (64 hexadecimal digits, no colons, for the approved signing certificate), and `API_BASE_URL` (real HTTPS origin of the no-wave `apps/api` deployment, no query or fragment; the workflow reads it from the variables context, so it must be a variable, not a secret).
- Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The app embeds no client key: the backend enforces authorization per request.

Use the correct existing production signing key if users already have the app. Back up and restrict it under the owner's control; loss or replacement can break upgrades. Obtain the expected SHA-256 fingerprint independently, for example using `keytool -list -v` on the approved keystore, and verify it out of band. The workflow rejects missing credentials, the standard debug alias/certificate, a fingerprint mismatch, unapproved app ID, mismatched package/version/permission, placeholder backend URL. Temporary files are removed after the job; GitHub runner and environment security remain owner responsibilities.

Set `version: MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`, with a positive Android version code no greater than 2100000000. Merge and validate that commit on `main`. Create a new immutable tag exactly `vMAJOR.MINOR.PATCH+BUILD` pointing to a commit reachable from `main`; only tag pushes trigger publication. The workflow uses the matching values as Flutter build name and number, checks the resulting APK metadata and signature, then creates a new GitHub Release with generated notes and a versioned APK name. It fails rather than replacing an existing release or asset. Never move/reuse release tags. The current `0.2.0+1` is the first real version: tag `v0.2.0+1` for it, and
raise the build number for every following release.

A successful CI fixture-signing test does not validate production credentials, store acceptance, device installation, backend configuration, or real signing. No production signing or publication has been performed by this change.

## iOS AltStore sideload IPA (no Apple Developer registration)

Tag releases additionally attach `belog-ios-vTAG-altstore.ipa`. It is built on the same tagged commit with `flutter build ios --release --no-codesign`, then ad-hoc signed (`codesign --sign -`, which embeds a signature structure but carries **no identity**) and packaged as a proper `Payload/Runner.app` IPA. It is deliberately **not** a distribution-signed IPA: no Apple Developer Program membership, distribution certificate, or provisioning profile exists for this project, and the artifact is not suitable for TestFlight or the App Store. For this tag-release workflow, the `production` environment gate (tag-on-`main` check, version alignment, Android signing inputs and public API configuration) applies to this artifact as well. For an iOS-only build independent of Android signing, use the manual workflow described in [mobile-packages.md](mobile-packages.md).

Install it with **AltStore using a free Apple ID** (this is the supported path and needs no paid developer registration): install AltServer on the Mac or PC that stays on the same Wi-Fi as the device, sign into AltStore with any personal Apple ID, then open the downloaded `.ipa` with AltStore on the device (Files app → Share → AltStore). AltStore and AltServer re-sign the app and its embedded frameworks with the user's personal-team certificate and provision the device; the exact registered identifiers are controlled by AltStore. Free-account limits apply: the signing profile expires after 7 days and is refreshed by AltStore in the background while AltServer is reachable, at most three sideloaded apps can be active per Apple ID, and up to ten new App IDs can be registered per 7 days. The app does not request paid-team capabilities such as push, iCloud, or app groups; a free personal team is the intended signing path, subject to AltStore and device verification.

Before upload, the shared packaging script verifies one `Payload/Runner.app`, archive safety and integrity, localized privacy descriptions, iPhoneOS device/arm64 binaries, bundle/version identity, and the packaged nested ad-hoc signatures. The resulting diagnostics are recorded in `ios-altstore-evidence`. A successful compile or signature-structure check does not prove that AltStore can re-sign/install the IPA, that the backend is reachable, or that the app runs correctly on a real device.
