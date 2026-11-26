import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Reads the editorial role off `GET /me` without caching it.
///
/// The answer belongs to a session, not to a device: `EDITOR_USER_IDS` and the
/// role column are both server-side and can change while this app is open, so
/// a persisted copy would eventually be the thing that lies to an editor.
class AccountEditorialRepositoryImpl implements AccountEditorialRepository {
  const AccountEditorialRepositoryImpl(this.client);

  final NowaveApiClient client;

  @override
  Future<Either<Failure, AccountEditorialCapacity>> readCapacity(
    NowaveSessionFence fence,
  ) async {
    try {
      // `followRedirects: false` because this is a session-scoped read: an
      // off-origin redirect would hand the answer to a server that is not the
      // one this fence authenticates against.
      final data = await client.getJson(
        '/me',
        sessionFence: fence,
        followRedirects: false,
      );
      if (data is! Map) {
        return left(_unanswered);
      }
      return right(_capacityOf(data));
    } on NowaveApiException catch (error) {
      if (error.statusCode == 401 && error.code != 'SESSION_CHANGED') {
        return left(
          const Failure(
            '登录已过期，请重新登录',
            kind: FailureKind.auth,
            code: 'auth.sessionExpired',
          ),
        );
      }
      // A deployment without this additive field answers 404/405 for the shape
      // of the question, which is the same fact as a 200 that omits it: nobody
      // has told us. Not a failure - a failure would leave an entry point
      // showing on an answer that never arrived.
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const Right(AccountEditorialCapacity.unknown);
      }
      if (error.statusCode >= 200 && error.statusCode < 300) {
        return left(_unanswered);
      }
      return left(mapErrorToFailure(error).forPresentation());
    } catch (error) {
      return left(mapErrorToFailure(error).forPresentation());
    }
  }

  /// Only a JSON boolean counts as an answer. A deployment that sends
  /// `"yes"`, `1`, or a string `"true"` is not agreeing to anything, and
  /// coercing it would invent a permission.
  static AccountEditorialCapacity _capacityOf(Map<dynamic, dynamic> me) {
    final isEditor = me['isEditor'];
    if (isEditor is! bool) return AccountEditorialCapacity.unknown;
    return isEditor
        ? AccountEditorialCapacity.granted
        : AccountEditorialCapacity.denied;
  }

  static const Failure _unanswered = Failure(
    '服务器没有说明这个账号的编辑身份',
    kind: FailureKind.server,
    code: 'editorial.unanswered',
  );
}
