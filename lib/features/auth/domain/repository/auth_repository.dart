import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/common/entities/user.dart';
import '../entities/sign_up_outcome.dart';

abstract interface class AuthRepository {
  /// Sign-up result: either a signed-in user or a pending e-mail
  /// confirmation ([SignUpOutcome.user] is null).
  Future<Either<Failure, SignUpOutcome>> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  });

  Future<Either<Failure, User>> loginWithEmailPassword({
    required String email,
    required String password,
  });

  Future<Either<Failure, void>> logout();

  Future<Either<Failure, User>> currentUser();

  Future<Either<Failure, void>> resendConfirmationEmail(String email);

  Future<Either<Failure, void>> sendPasswordResetEmail(String email);
}
