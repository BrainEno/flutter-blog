import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/repository/password_recovery_repository.dart';
import 'package:fpdart/fpdart.dart';

class ResetPassword implements UseCase<void, ResetPasswordParams> {
  const ResetPassword(this.repository);

  final PasswordRecoveryRepository repository;

  @override
  Future<Either<Failure, void>> call(ResetPasswordParams params) {
    return repository.resetPassword(
      token: params.token,
      password: params.password,
    );
  }
}

class ResetPasswordParams {
  const ResetPasswordParams({required this.token, required this.password});

  final String token;
  final String password;
}
