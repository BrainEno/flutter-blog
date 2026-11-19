import 'dart:collection';

/// One sanitized diagnostics record: a single pre-scrubbed line plus its
/// timestamp. Everything the buffer ever learns about a failure is on
/// this object, which is what makes the export safe to hand to support:
/// category, HTTP status, request path (never the query), duration and
/// error type - never tokens, e-mails, bodies or query parameters.
class DiagnosticsEntry {
  final DateTime at;
  final String line;

  const DiagnosticsEntry(this.at, this.line);
}

/// Bounded in-process ring buffer of sanitized failure records
/// (issue #49).
///
/// Privacy model, in one direction: nothing leaves the device on its own.
/// The buffer lives in memory only - no disk, no network, no telemetry -
/// and dies with the process. The only reader is the user, through the
/// explicit diagnostics dialog on the about page, which shows the plain
/// text before anything is copied, shared or exported. Exporting writes a
/// scratch text file solely to hand it to the system share sheet the user
/// opened (issue #306; see `diagnostics_file_export.dart`).
class DiagnosticsBuffer {
  DiagnosticsBuffer({
    this.capacity = 200,
    this.maxAge = defaultMaxAge,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Records older than this are dropped even when the buffer has room
  /// (issue #306). A long-lived process should not hand support a failure
  /// from yesterday's unrelated session, and a bounded window keeps the
  /// exported file about the problem the user is reporting now.
  static const Duration defaultMaxAge = Duration(hours: 24);

  /// How many entries survive; the oldest are dropped first. Errors are
  /// rare enough that 200 failure lines comfortably cover a support
  /// conversation, while a request storm cannot grow memory unbounded.
  final int capacity;

  /// Upper bound on the age of a surviving record; see [defaultMaxAge].
  final Duration maxAge;

  /// Injectable for tests; production reads the wall clock.
  final DateTime Function() _clock;

  final ListQueue<DiagnosticsEntry> _entries = ListQueue<DiagnosticsEntry>();

  /// Oldest first; newest last. Records older than [maxAge] are pruned
  /// before the snapshot is taken.
  List<DiagnosticsEntry> get entries {
    _pruneExpired();
    return List.unmodifiable(_entries);
  }

  bool get isEmpty {
    _pruneExpired();
    return _entries.isEmpty;
  }

  void _add(String line) {
    _entries.add(DiagnosticsEntry(_clock(), line));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _pruneExpired();
  }

  /// Entries are appended in clock order, so expired ones are always at the
  /// front. A clock that steps backwards cannot resurrect anything: an entry
  /// stamped in the future is kept until it, too, falls out of the window.
  void _pruneExpired() {
    final cutoff = _clock().subtract(maxAge);
    while (_entries.isNotEmpty && _entries.first.at.isBefore(cutoff)) {
      _entries.removeFirst();
    }
  }

  /// Records an application-level error: the static message plus the
  /// error's runtime type. The error object itself (whose toString can
  /// embed anything) is deliberately not recorded.
  void recordError(String message, Object? error) {
    // The message is a caller-owned static category string; scrubbing
    // it whole is safe because nothing after a '?' or '#' is ever part
    // of the contract.
    _add(
      'error ${_scrubFragment(message)} '
      '(${error?.runtimeType ?? 'no error object'})',
    );
  }

  /// Records a failed request summary. [path] is sanitized to the URL
  /// path proper, so the status and duration after it survive intact.
  void recordRequest(
    String method,
    String path,
    int statusCode,
    int durationMs,
  ) {
    _add(
      'request $method ${_scrubFragment(path)} -> $statusCode '
      '(${durationMs}ms)',
    );
  }

  /// Records a request that exceeded its timeout budget.
  void recordTimeout(String method, String path, int budgetMs) {
    _add('timeout $method ${_scrubFragment(path)} (budget ${budgetMs}ms)');
  }

  /// Records a request that never got a response because the transport
  /// failed (no route, connection reset, ...). [errorType] is the thrown
  /// error's runtime type - the most common support case ("no network")
  /// must not leave the buffer empty.
  void recordUnreachable(String method, String path, String errorType) {
    _add('request $method ${_scrubFragment(path)} unreachable ($errorType)');
  }

  /// Records a connectivity probe that failed before any response arrived.
  /// [path] is the probe target (sanitized like a request path), and
  /// [errorType] is the thrown error's runtime type.
  void recordProbe(String path, String errorType) {
    _add('probe GET ${_scrubFragment(path)} failed ($errorType)');
  }

  /// Records a probe that ran out of budget without a definite failure.
  /// [elapsedMs] is the measured wait and [budgetMs] the configured bound.
  void recordProbeInconclusive(String path, int elapsedMs, int budgetMs) {
    _add(
      'probe GET ${_scrubFragment(path)} inconclusive '
      '(TimeoutException after ${elapsedMs}ms, budget ${budgetMs}ms)',
    );
  }

  /// Records a response that arrived but could not be decoded. The status
  /// code is kept; [reason] is a fixed token like `non-utf8` or `non-json`,
  /// never part of the body.
  void recordMalformed(
    String method,
    String path,
    int statusCode,
    String reason,
  ) {
    _add(
      'response $method ${_scrubFragment(path)} -> $statusCode '
      'malformed ($reason)',
    );
  }

  void clear() => _entries.clear();

  /// Defense in depth: everything from a '?' or '#' on is dropped, so a
  /// query string or fragment can never reach the buffer - even when a
  /// future caller misbehaves.
  static String _scrubFragment(String part) =>
      part.split('?').first.split('#').first;

  /// Plain-text export, newest first (the most recent failure is what
  /// support reads first). One entry per line, no decoration.
  ///
  /// [limit] keeps only the newest records; null exports everything that is
  /// still inside the [maxAge] window.
  String export({int? limit}) {
    _pruneExpired();
    if (_entries.isEmpty) return '';
    final buffer = StringBuffer();
    var newestFirst = _entries.toList().reversed;
    if (limit != null) newestFirst = newestFirst.take(limit < 0 ? 0 : limit);
    for (final entry in newestFirst) {
      buffer.writeln('${entry.at.toIso8601String()} ${entry.line}');
    }
    return buffer.toString().trimRight();
  }
}
