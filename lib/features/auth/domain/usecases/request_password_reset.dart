import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/repository/password_recovery_repository.dart';
import 'package:fpdart/fpdart.dart';

class RequestPasswordReset
    implements UseCase<void, RequestPasswordResetParams> {
  const RequestPasswordReset(this.repository);

  final PasswordRecoveryRepository repository;

  @override
  Future<Either<Failure, void>> call(RequestPasswordResetParams params) {
    return repository.requestPasswordReset(email: params.email);
  }
}

class RequestPasswordResetParams {
  const RequestPasswordResetParams({required this.email});

  final String email;
}
