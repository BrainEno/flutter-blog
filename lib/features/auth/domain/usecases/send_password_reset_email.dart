import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Sends a password-recovery e-mail. The link inside opens the app via the
/// auth callback scheme and establishes a session, after which the user
/// sets a new password in "账号安全".
class SendPasswordResetEmail implements UseCase<void, String> {
  final AuthRepository authRepository;
  const SendPasswordResetEmail(this.authRepository);

  @override
  Future<Either<Failure, void>> call(String email) async {
    return await authRepository.sendPasswordResetEmail(email);
  }
}
