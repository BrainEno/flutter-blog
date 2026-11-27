import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:fpdart/fpdart.dart';

/// Reads the one account fact the editorial screens need, and nothing else.
///
/// It is its own repository rather than a method on `AuthRepository` for the
/// same reason the session list is: one narrow, fenced read that a screen can
/// hold without pulling the whole sign-in contract into a test double.
abstract interface class AccountEditorialRepository {
  /// Asks `GET /me` who this account is, fenced to the [fence] that asked.
  ///
  /// A failure is reported as a [Failure] instead of [AccountEditorialCapacity
  /// .unknown]: "the request did not answer" and "the answer named no role"
  /// are different facts, and a screen that guessed from the first would keep
  /// an entry point alive on a network that can no longer justify it.
  Future<Either<Failure, AccountEditorialCapacity>> readCapacity(
    NowaveSessionFence fence,
  );
}
