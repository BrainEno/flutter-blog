import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
import 'package:fpdart/fpdart.dart';

/// An online-only, read-only view for the initiating account and session.
abstract interface class AccountSessionRepository {
  Future<Either<Failure, List<AccountSession>>> listSessions(
    NowaveSessionFence fence,
  );
}
