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
    _entries.add(DiagnosticsEntry(DateTime.now(), _scrub(line)));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  /// Records an application-level error: the static message plus the
  /// error's runtime type. The error object itself (whose toString can
  /// embed anything) is deliberately not recorded.
  void recordError(String message, Object? error) {
    _add('error $message (${error?.runtimeType ?? 'no error object'})');
  }

  /// Records a failed request summary. [path] is the URL path only.
  void recordRequest(
    String method,
    String path,
    int statusCode,
    int durationMs,
  ) {
    _add('request $method $path -> $statusCode (${durationMs}ms)');
  }

  /// Records a request that exceeded its timeout budget.
  void recordTimeout(String method, String path, int budgetMs) {
    _add('timeout $method $path (budget ${budgetMs}ms)');
  }

  void clear() => _entries.clear();

  /// Defense in depth: even if a caller ever passes a path or message
  /// carrying a query string or fragment, it never reaches the buffer.
  static String _scrub(String line) => line.split('?').first.split('#').first;

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
