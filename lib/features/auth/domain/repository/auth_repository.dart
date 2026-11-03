import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

abstract interface class AuthRepository {
  /// Sign-up. The no-wave backend returns a session immediately (no e-mail
  /// confirmation step), so a successful sign-up is a signed-in user.
  ///
  /// [intent] orders authentication attempts (see `AuthIntentGate`): only the
  /// newest one may adopt a session, so a slow older response cannot replace
  /// the account the user chose afterwards.
  Future<Either<Failure, User>> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
    int? intent,
  });

  Future<Either<Failure, User>> loginWithEmailPassword({
    required String email,
    required String password,
    int? intent,
  });

  Future<Either<Failure, void>> logout();

  Future<Either<Failure, User>> currentUser();
}
