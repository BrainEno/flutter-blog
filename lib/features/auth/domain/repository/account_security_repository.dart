import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

/// Operations that prove possession of the current account credential.
abstract interface class AccountSecurityRepository {
  /// Changes the password for the specific session that opened the form.
  ///
  /// Failures do not carry the submitted passwords or raw transport errors.
  /// A transport error after sending may mean the change already happened.
  Future<Either<Failure, void>> changePassword({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newPassword,
  });
}
