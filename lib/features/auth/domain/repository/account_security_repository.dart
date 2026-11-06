import 'package:belog/core/error/failures.dart';
import 'package:belog/features/auth/domain/email_verification.dart';
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

  /// The address on file and whether the server has proof of it.
  ///
  /// A read, so it may refresh an expired access token; it is still fenced to
  /// the identity that asked, and returns nothing at all if that identity is
  /// replaced while the answer is in flight.
  Future<Either<Failure, AccountEmailStatus>> readEmailStatus({
    required String expectedUserId,
    required int expectedSessionGeneration,
  });

  /// Asks the server to mail a verification link to the account's own address.
  ///
  /// `MAIL_DISABLED` means the deployment has no mail transport - a permanent
  /// answer that retrying will not change, and one the caller must state as
  /// such instead of implying a message is on its way. Each request costs one
  /// of the account's five attempts per hour, so this is never retried
  /// automatically.
  Future<Either<Failure, EmailVerificationRequest>> requestEmailVerification({
    required String expectedUserId,
    required int expectedSessionGeneration,
  });

  /// Redeems a mailed verification token.
  ///
  /// Unauthenticated by design: the token *is* the proof, so it also works for
  /// a link opened on another device. Tokens are single-use and expire after a
  /// day; the only way to tell "already used" from "expired" is to ask, and the
  /// server answers both with `UNAUTHENTICATED`. A transport failure after
  /// sending may have consumed the token, so this is never retried.
  Future<Either<Failure, void>> verifyEmailToken({required String token});
}
