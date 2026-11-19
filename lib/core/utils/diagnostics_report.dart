import 'diagnostics_buffer.dart';

/// Identifies the layout of an exported diagnostics file so a support reader
/// (or a future parser) can tell versions apart. Bump it when the section
/// order or a fixed line changes.
const String kDiagnosticsExportFormat = 'belog-diagnostics/1';

/// How many of the newest records an exported file carries (issue #306).
///
/// The buffer itself keeps up to 200 records for 24 hours; a support
/// conversation needs the most recent failures, and a smaller file is easier
/// to review before handing it over.
const int kDiagnosticsExportMaxEntries = 100;

/// Composes the plain-text document behind "export log file" (issue #306).
///
/// Layout, top to bottom:
/// 1. a fixed title, the format tag, the UTC generation instant and a scope
///    line stating that the export is user-initiated and never uploaded;
/// 2. the sanitized context [header] (app version, build, platform, locale
///    and API origin - see `buildDiagnosticsHeader`);
/// 3. a count line, then the newest [maxEntries] records newest-first.
///
/// [entries] are expected oldest-first, exactly as `DiagnosticsBuffer.entries`
/// returns them. The whole document goes through [redactDiagnosticsText] as a
/// last line of defense: the buffer only stores pre-scrubbed lines, but a
/// future caller could still pass a message that embeds a credential.
String composeDiagnosticsExport({
  required String header,
  required List<DiagnosticsEntry> entries,
  required DateTime generatedAt,
  Duration window = DiagnosticsBuffer.defaultMaxAge,
  int maxEntries = kDiagnosticsExportMaxEntries,
}) {
  final cap = maxEntries < 0 ? 0 : maxEntries;
  final newestFirst = entries.reversed.take(cap).toList(growable: false);
  final trimmedHeader = header.trim();
  final lines = <String>[
    'No Wave diagnostics export',
    'format $kDiagnosticsExportFormat',
    'generated ${generatedAt.toUtc().toIso8601String()}',
    'scope user-initiated export; nothing is uploaded automatically',
    if (trimmedHeader.isNotEmpty) trimmedHeader,
    'records ${newestFirst.length} of ${entries.length} '
        '(newest first, window ${describeDiagnosticsWindow(window)}, '
        'cap $cap)',
    '',
    if (newestFirst.isEmpty) '(no failures recorded in this window)',
    for (final entry in newestFirst)
      '${entry.at.toIso8601String()} ${entry.line}',
  ];
  return '${redactDiagnosticsText(lines.join('\n'))}\n';
}

/// Human-readable retention window: whole hours when possible, minutes
/// otherwise (`24h`, `90m`).
String describeDiagnosticsWindow(Duration window) {
  if (window.inMinutes > 0 && window.inMinutes % 60 == 0) {
    return '${window.inHours}h';
  }
  if (window.inMinutes > 0) return '${window.inMinutes}m';
  return '${window.inSeconds}s';
}

final RegExp _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

final RegExp _authorizationScheme = RegExp(
  r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);

final RegExp _jwt = RegExp(
  r'\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*',
);

final RegExp _secretAssignment = RegExp(
  r'\b(access_token|refresh_token|id_token|plan_?token|token|password|passwd|'
  r'secret|client_secret|api_?key|authorization|cookie|set-cookie)\b'
  r'''(\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s&,;)\]}]+)''',
  caseSensitive: false,
);

/// Replaces anything that looks like a credential or an e-mail address.
///
/// This is defense in depth for the export path, not the primary privacy
/// control: `DiagnosticsBuffer` never records bodies, query strings, error
/// texts or headers in the first place. The patterns are deliberately broad
/// (a false positive costs a support reader one word; a false negative leaks
/// an account), but they never touch the fixed vocabulary of the report -
/// timestamps, HTTP methods, paths, status codes, durations and error types.
String redactDiagnosticsText(String text) {
  var redacted = text.replaceAllMapped(
    _authorizationScheme,
    (match) => '${match.group(1)} <redacted>',
  );
  redacted = redacted.replaceAll(_jwt, '<redacted-token>');
  redacted = redacted.replaceAllMapped(
    _secretAssignment,
    (match) => '${match.group(1)}${match.group(2)}<redacted>',
  );
  return redacted.replaceAll(_email, '<redacted-email>');
}
