import 'package:belog/core/utils/article_resource_url.dart';
import 'package:url_launcher/url_launcher.dart';

/// The launcher an [ArticleResourceOpener] uses instead of the platform.
///
/// A test supplies one to record the exact address that would have left the
/// app, which is the only way to prove that a widget handed over the resolved
/// value rather than the raw server text.
typedef ArticleResourceLaunch = Future<bool> Function(Uri uri);

/// What happened when the app tried to hand an address to the operating system.
enum ArticleResourceOutcome {
  /// The whitelist refused the value. Nothing was launched, and the address is
  /// not a link this app can open - the reader gets the invalid-link message,
  /// not a failure to reach the platform.
  rejected,

  /// The address was safe to open but the platform did not open it: no
  /// handler for the scheme, or the launcher reported failure.
  unavailable,

  /// The address was passed to the platform and accepted.
  opened,
}

/// The one door between a server-supplied address and `launchUrl`.
///
/// Splitting the rule in two is what let it drift: `resolveArticleResourceUrl`
/// decides what may be opened, but every caller then had to remember to consult
/// it, to pick `LaunchMode.externalApplication`, and to decide what a refusal
/// means for the reader. Three call sites grew three different policies around
/// the same plugin call, and one of them skipped the whitelist entirely, which
/// is how a profile's `javascript:` site URL reached the operating system
/// (issue #369). Under one owner the check and the hand-off cannot disagree,
/// and `test/unit/core/external_link_guard_test.dart` fails the suite if a
/// `launchUrl(` call site appears anywhere else in `lib/`.
///
/// Both knobs are null in the app, where the values come from the compiled-in
/// `WEB_BASE_URL` and the real platform launcher.
class ArticleResourceOpener {
  const ArticleResourceOpener({this.webBaseUrl, this.launch});

  /// The origin site-relative values resolve against.
  ///
  /// Null defers to `AppSecrets.webBaseUrl`, and with neither configured a
  /// relative value stays inert: the web app is a separate origin from the API,
  /// so guessing it would open someone else's site.
  final String? webBaseUrl;

  /// The launcher, replaced only by tests.
  ///
  /// Null uses [launchUrl] with [LaunchMode.externalApplication], which is what
  /// a browser or the map app needs: an in-app web view would be a second
  /// session the reader did not ask for.
  final ArticleResourceLaunch? launch;

  /// Whether [value] is an address this app may open.
  ///
  /// A widget that renders a link asks this instead of calling
  /// [resolveArticleResourceUrl] itself, so the choice between a tappable
  /// button and inert copy is made by the same rule as the launch.
  bool accepts(String value) => _resolve(value) != null;

  /// Opens [value] when the whitelist allows it.
  ///
  /// The raw text is passed in rather than a resolved `Uri` so that no caller
  /// can hold a validated value and then launch a different one; a resolved
  /// address could be mutated, re-parsed or assembled from a second field on
  /// the way to [launchUrl].
  Future<ArticleResourceOutcome> open(String value) async {
    final uri = _resolve(value);
    if (uri == null) return ArticleResourceOutcome.rejected;
    final opened = await (launch ?? _launchExternally)(uri);
    return opened
        ? ArticleResourceOutcome.opened
        : ArticleResourceOutcome.unavailable;
  }

  Uri? _resolve(String value) =>
      resolveArticleResourceUrl(value, webBaseUrl: webBaseUrl);
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
