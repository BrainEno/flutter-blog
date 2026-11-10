import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

/// The anonymous, one-time e-mail password recovery flow.
///
/// A successful request means the server accepted the request, not that an
/// address exists or a message was delivered. Resetting a password invalidates
/// every session for the recovered account.
abstract interface class PasswordRecoveryRepository {
  Future<Either<Failure, void>> requestPasswordReset({
    required String email,
  });

  /// [token] may be the raw one-time token or the whole reset link copied from
  /// an e-mail. Implementations must extract and send only the token itself.
  Future<Either<Failure, void>> resetPassword({
    required String token,
    required String password,
  });
}
