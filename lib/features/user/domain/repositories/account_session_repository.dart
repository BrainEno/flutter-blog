import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
import 'package:belog/features/user/domain/entities/session_revoke_outcome.dart';
import 'package:fpdart/fpdart.dart';

/// An online-only view of the initiating account's sessions, plus the two
/// revocation calls the server offers.
///
/// Everything here is fenced to the account and session generation that asked;
/// nothing is cached, and no revocation is retried automatically.
abstract interface class AccountSessionRepository {
  Future<Either<Failure, List<AccountSession>>> listSessions(
    NowaveSessionFence fence,
  );

  /// Ends exactly one session.
  ///
  /// A 404 is reported as [SessionRevokeOutcome.alreadyEnded] rather than a
  /// failure: on a page listing this account's own rows, "not found" means the
  /// session is no longer signed in, which is what the caller wanted.
  Future<Either<Failure, SessionRevokeOutcome>> revokeSession(
    NowaveSessionFence fence,
    String sessionId,
  );

  /// Ends every session except the one making the call, and returns how many
  /// were ended.
  ///
  /// The server spares the calling session only when the access token names it.
  /// A token without that claim spares nothing - the caller must warn about
  /// that case instead of promising the current device survives.
  Future<Either<Failure, int>> revokeOtherSessions(NowaveSessionFence fence);
}
