import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Re-sends the sign-up confirmation e-mail.
class ResendConfirmationEmail implements UseCase<void, String> {
  final AuthRepository authRepository;
  const ResendConfirmationEmail(this.authRepository);

  @override
  Future<Either<Failure, void>> call(String email) async {
    return await authRepository.resendConfirmationEmail(email);
  }
}
