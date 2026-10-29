import 'package:belog/core/error/failures.dart';

/// Exception thrown by data sources, converted to a [Failure] by the
/// repository layer.
///
/// [message] must be display-safe (see [Failure]); the raw error travels in
/// [cause] for diagnostics only.
class ServerException implements Exception {
  final String message;
  final FailureKind kind;
  final Object? cause;

  const ServerException(
    this.message, {
    this.kind = FailureKind.server,
    this.cause,
  });

  /// Converts this exception into the failure the UI receives.
  Failure toFailure() => Failure(message, kind: kind, cause: cause);

  @override
  String toString() => 'ServerException($kind, $message)';
}
