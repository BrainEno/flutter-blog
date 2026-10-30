import 'package:flutter/foundation.dart';

import 'diagnostics_buffer.dart';

/// Minimal logging facade.
///
/// Logs go to the console in debug builds only - there is no telemetry or
/// remote sink, and nothing is logged in release/profile builds. Callers
/// must never pass tokens, passwords, emails or other personal data.
///
/// On top of the console output, a bounded in-memory buffer of sanitized
/// failure records ([diagnostics]) survives in release builds so a user
/// can hand something to support beyond "it does not work" (issue #49).
/// It records only categories, HTTP status codes, request paths without
/// query strings, durations and error types - never tokens, emails,
/// bodies or query parameters - and nothing leaves the device.
class AppLogger {
  AppLogger._();

  /// Process-local diagnostics ring buffer; discarded on app exit.
  static final DiagnosticsBuffer diagnostics = DiagnosticsBuffer();

  /// Diagnostic noise for development.
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[belog] $message');
    }
  }

  /// Something failed. [error] and [stackTrace] are development-only
  /// context; they are never shown to users.
  ///
  /// The diagnostics buffer records the (static, caller-owned) message
  /// and the error's runtime type only - the error object's own text can
  /// embed anything and is not captured.
  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    diagnostics.recordError(message, error);
    if (kDebugMode) {
      debugPrint('[belog] $message${error == null ? '' : ' | $error'}');
      if (stackTrace != null) {
        debugPrint('$stackTrace');
      }
    }
  }

  /// Records a failed HTTP exchange into the diagnostics buffer
  /// (release builds included). [path] is the URL path only; the query
  /// string never reaches the buffer.
  static void request(
    String method,
    String path,
    int statusCode,
    int durationMs,
  ) {
    diagnostics.recordRequest(method, path, statusCode, durationMs);
  }

  /// Records an HTTP exchange that exceeded its timeout budget.
  static void requestTimeout(String method, String path, int budgetMs) {
    diagnostics.recordTimeout(method, path, budgetMs);
  }

  /// Records an HTTP exchange that failed before any response arrived
  /// (socket/transport errors). [errorType] is the error's runtime type.
  static void requestUnreachable(String method, String path, String errorType) {
    diagnostics.recordUnreachable(method, path, errorType);
  }

  /// Records a response whose body could not be decoded; [reason] is a
  /// fixed token (`non-utf8`, `non-json`), never body content.
  static void responseMalformed(
    String method,
    String path,
    int statusCode,
    String reason,
  ) {
    diagnostics.recordMalformed(method, path, statusCode, reason);
  }

  /// Plain-text diagnostics report, newest first; empty when nothing
  /// failed. The user sees exactly this text before copying it.
  static String diagnosticsReport() => diagnostics.export();

  /// Empties the diagnostics buffer.
  static void clearDiagnostics() => diagnostics.clear();
}
