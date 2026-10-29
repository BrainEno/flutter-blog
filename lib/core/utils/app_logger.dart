import 'package:flutter/foundation.dart';

/// Minimal logging facade.
///
/// Logs go to the console in debug builds only - there is no telemetry or
/// remote sink, and nothing is logged in release/profile builds. Callers
/// must never pass tokens, passwords, emails or other personal data.
class AppLogger {
  AppLogger._();

  /// Diagnostic noise for development.
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[belog] $message');
    }
  }

  /// Something failed. [error] and [stackTrace] are development-only
  /// context; they are never shown to users.
  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint('[belog] $message${error == null ? '' : ' | $error'}');
      if (stackTrace != null) {
        debugPrint('$stackTrace');
      }
    }
  }
}
