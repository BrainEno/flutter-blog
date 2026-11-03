import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/common/entities/user.dart';

class UserLogin implements UseCase<User, UserLoginParams> {
  final AuthRepository authRepository;

  const UserLogin(this.authRepository);

  @override
  Future<Either<Failure, User>> call(UserLoginParams params) async {
    return await authRepository.loginWithEmailPassword(
      email: params.email,
      password: params.password,
      intent: params.intent,
    );
  }
}

class UserLoginParams {
  final String email;
  final String password;

  /// Ordering id from `AuthIntentGate`; only the newest intent may win.
  final int? intent;

  UserLoginParams({required this.email, required this.password, this.intent});
}
