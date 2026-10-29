/// Deep-link configuration for Supabase auth e-mails.
///
/// The scheme must be registered on every platform:
/// - Android: intent-filter in `android/app/src/main/AndroidManifest.xml`
/// - iOS: `CFBundleURLTypes` in `ios/Runner/Info.plist`
///
/// The callback URL must also be whitelisted in the Supabase dashboard
/// (Authentication -> URL Configuration -> Redirect URLs); see README.md
/// "深链与邮箱流程" for the owner checklist.
library;

/// Custom URL scheme the app claims for auth callbacks.
const String kAuthCallbackScheme = 'belog';

/// Redirect URL embedded in sign-up confirmation and password-recovery
/// e-mails. Keep in sync with the platform configs above and the Supabase
/// redirect URL whitelist.
const String kAuthCallbackUrl = 'belog://auth-callback';
