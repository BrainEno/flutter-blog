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

  /// Moves the account to another address and returns the address the server
  /// stored (trimmed and lowercased by the server, not by the caller).
  ///
  /// The current password travels with it, exactly as for [changePassword]:
  /// whoever controls the address controls recovery, so a stolen session alone
  /// must not be able to move it. The new address is unverified afterwards, and
  /// the server sends no mail. Sessions are not revoked.
  ///
  /// The returned address is the server's answer, because "the change was
  /// accepted" and "this is the address on file" are two different claims and
  /// only the second one may be shown as a fact.
  Future<Either<Failure, String>> changeEmail({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newEmail,
  });
}
