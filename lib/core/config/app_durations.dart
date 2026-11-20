/// Every duration the app *waits* for, in one place (#295).
///
/// A duration is one of two things: how the app moves, or how long it waits.
/// Motion comes from `NoWaveMotion` in `core/design/design_tokens.dart`. This
/// file owns the second kind - request and upload timeouts, probe windows,
/// boot bounds, debounces, dwell times and retention windows - so a change to
/// the timeout policy is one edit instead of a search across features.
///
/// The values are grouped by the question they answer, and each one carries
/// why it has the value it has. `test/unit/design/no_magic_durations_test.dart`
/// rejects a new `Duration(...)` literal anywhere else under `lib/`, except
/// for the few files whose durations are computed rather than configured.
abstract final class AppDurations {
  // --- Network ------------------------------------------------------------

  /// Each phase (send, body read) of an ordinary JSON exchange.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Each phase of a single media upload (#295 Q11, decided in round 4).
  ///
  /// `_request` applies the budget twice: once until the response headers
  /// arrive (the whole request body has to be sent and the server has to
  /// re-encode the image to WebP first), and once more to read the response.
  /// The first phase has to carry the largest image the server accepts,
  /// `AppLimits.mediaUploadMaxBytes` (8 MiB). Over a weak mobile uplink of
  /// `AppLimits.slowUplinkBytesPerSecond` (1 Mbit/s) that alone takes about
  /// 67 s; the ordinary 30 s budget would abort every image above roughly
  /// 3.7 MB on such a link and turn a slow success into a failure the user has
  /// to retry by hand. 90 s covers the transfer plus re-encode headroom while
  /// a stalled connection still fails inside a bound instead of hanging the
  /// editor. `app_config_test.dart` keeps this budget tied to the size limit.
  static const Duration mediaUploadTimeout = Duration(seconds: 90);

  /// A Notion import copies remote images server-side before it answers.
  static const Duration notionImportTimeout = Duration(minutes: 2);

  /// How long the health probe may take before the result is inconclusive.
  static const Duration healthProbeTimeout = Duration(seconds: 3);

  /// How long a successful health probe is trusted. Deliberately short: a
  /// business request can still fail inside it.
  static const Duration healthProbeSuccessTtl = Duration(seconds: 2);

  /// The first backoff after a connection closed before a response; later
  /// retries double it and add up to the same amount of jitter.
  static const Duration connectionRetryInitialDelay = Duration(
    milliseconds: 500,
  );

  // --- Session ------------------------------------------------------------

  /// How early an access token is refreshed before it expires.
  static const Duration sessionRefreshLead = Duration(seconds: 30);

  // --- Boot ---------------------------------------------------------------

  /// How long the cold-start session restore may hold back the first route.
  /// Normally it resolves well under a second; the bound only guards against
  /// a hung network so the app still becomes usable.
  static const Duration bootSessionRestore = Duration(seconds: 3);

  /// The language preference is one small row. Bounding it only keeps a
  /// corrupt store from delaying the app.
  static const Duration bootLanguageRestore = Duration(seconds: 2);

  /// The About page's package-info lookup. The diagnostics report must never
  /// wait on the platform channel; a slow lookup degrades the header instead.
  static const Duration packageInfoLookup = Duration(seconds: 2);

  // --- Input and feedback -------------------------------------------------

  /// The pause after the last keystroke before any search box queries.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Material's own display time for a snackbar; the app default.
  static const Duration snackBarDefault = Duration(milliseconds: 4000);

  /// Transient feedback the user can act on again right away.
  static const Duration snackBarShort = Duration(seconds: 2);

  /// The quiet period after the last edit before the editor saves a local
  /// draft. It only writes to the device, never to the server.
  static const Duration editorAutoSave = Duration(seconds: 2);

  // --- Retention and retry schedules --------------------------------------

  /// Diagnostics records older than this are dropped even when there is room.
  static const Duration diagnosticsMaxAge = Duration(hours: 24);

  /// The wait before each publish-queue retry: the first entry follows the
  /// first failure, and the last entry repeats for every later attempt.
  static const List<Duration> publishRetrySchedule = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
    Duration(hours: 3),
  ];

  /// The publish-queue backoff after [attempts] failed attempts.
  static Duration publishRetryAfter(int attempts) {
    if (attempts < 0) return publishRetrySchedule.first;
    if (attempts >= publishRetrySchedule.length) {
      return publishRetrySchedule.last;
    }
    return publishRetrySchedule[attempts];
  }
}
