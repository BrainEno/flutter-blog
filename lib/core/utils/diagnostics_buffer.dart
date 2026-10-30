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
/// Privacy model, in one direction: nothing leaves the device. The
/// buffer lives in memory only - no disk, no network, no telemetry -
/// and dies with the process. The only reader is the user, through the
/// explicit "copy diagnostics" entry on the about page, which shows the
/// plain text before anything is copied.
class DiagnosticsBuffer {
  DiagnosticsBuffer({this.capacity = 200});

  /// How many entries survive; the oldest are dropped first. Errors are
  /// rare enough that 200 failure lines comfortably cover a support
  /// conversation, while a request storm cannot grow memory unbounded.
  final int capacity;

  final ListQueue<DiagnosticsEntry> _entries = ListQueue<DiagnosticsEntry>();

  /// Oldest first; newest last.
  List<DiagnosticsEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void _add(String line) {
    _entries.add(DiagnosticsEntry(DateTime.now(), line));
    while (_entries.length > capacity) {
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
  String export() {
    if (_entries.isEmpty) return '';
    final buffer = StringBuffer();
    for (final entry in _entries.toList().reversed) {
      buffer.writeln('${entry.at.toIso8601String()} ${entry.line}');
    }
    return buffer.toString().trimRight();
  }
}
