import 'package:belog/core/error/failures.dart';

/// Exception thrown by data sources, converted to a [Failure] by the
/// repository layer.
///
/// [message] must be display-safe (see [Failure]); the raw error travels in
/// [cause] for diagnostics only. [code] is a stable machine-readable
/// identifier threaded into [Failure.code] so the presentation layer can
/// localize without matching on (Chinese) message text (issue #24).
class ServerException implements Exception {
  final String message;
  final FailureKind kind;
  final String? code;
  final Object? cause;

  const ServerException(
    this.message, {
    this.kind = FailureKind.server,
    this.code,
    this.cause,
  });

  /// Converts this exception into the failure the UI receives.
  Failure toFailure() =>
      Failure(message, kind: kind, code: code, cause: cause);

  @override
  String toString() => 'ServerException($kind, $message)';
}
