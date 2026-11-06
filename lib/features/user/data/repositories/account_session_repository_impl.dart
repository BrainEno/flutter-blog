import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
import 'package:belog/features/user/domain/entities/session_revoke_outcome.dart';
import 'package:belog/features/user/domain/repositories/account_session_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The no-wave session list is not cached, persisted or logged. A fence is
/// passed all the way to the HTTP client so a 401 cannot retry as a new user.
class AccountSessionRepositoryImpl implements AccountSessionRepository {
  const AccountSessionRepositoryImpl(this.client);

  final NowaveApiClient client;

  @override
  Future<Either<Failure, List<AccountSession>>> listSessions(
    NowaveSessionFence fence,
  ) async {
    try {
      final data = await client.getJson(
        '/me/sessions',
        sessionFence: fence,
        followRedirects: false,
      );
      return right(_parseSessions(data));
    } catch (error) {
      if (error is NowaveApiException) {
        // A deployment can predate this additive API. A 404/405 does not
        // establish its version, so the UI says only that it is unavailable.
        if (error.statusCode == 404 || error.statusCode == 405) {
          return left(
            const Failure(
              '此服务器暂不提供登录会话列表',
              kind: FailureKind.server,
              code: 'sessions.unavailable',
            ),
          );
        }
        if (error.statusCode == 401 && error.code != 'SESSION_CHANGED') {
          return left(
            const Failure(
              '登录已过期，请重新登录',
              kind: FailureKind.auth,
              code: 'server.UNAUTHENTICATED',
            ),
          );
        }
        if (error.statusCode == 429) {
          return left(
            const Failure(
              '操作过于频繁，请稍后再试',
              kind: FailureKind.server,
              code: 'server.RATE_LIMITED',
            ),
          );
        }
        // The shared client reports a malformed success envelope as HTTP_200.
        if (error.statusCode >= 200 && error.statusCode < 300) {
          return left(_parseFailure());
        }
      }
      // The mapper classifies network, timeout, auth, server, and parse
      // failures. Drop its diagnostic cause: this page never needs raw data.
      return left(mapErrorToFailure(error).forPresentation());
    }
  }

  @override
  Future<Either<Failure, SessionRevokeOutcome>> revokeSession(
    NowaveSessionFence fence,
    String sessionId,
  ) async {
    // A `.` or `..` segment would be normalised away by the URI resolver and
    // could reach a different endpoint than the one named here. Real ids never
    // take that shape, so refuse instead of resolving something else.
    final id = sessionId.trim();
    if (id.isEmpty || id != sessionId || id == '.' || id == '..') {
      return left(_invalidSession);
    }
    try {
      final data = await client.deleteJson(
        '/me/sessions/${Uri.encodeComponent(id)}',
        sessionFence: fence,
        followRedirects: false,
      );
      if (data is Map && data['ok'] == true) {
        return right(SessionRevokeOutcome.ended);
      }
      // A 2xx this build cannot read may still have ended the session.
      return left(_revokeUnknown);
    } on NowaveApiException catch (error) {
      if (error.statusCode == 404) {
        return right(SessionRevokeOutcome.alreadyEnded);
      }
      return left(_revokeFailure(error));
    } catch (_) {
      return left(_revokeUnknown);
    }
  }

  @override
  Future<Either<Failure, int>> revokeOtherSessions(
    NowaveSessionFence fence,
  ) async {
    try {
      final data = await client.deleteJson(
        '/me/sessions',
        sessionFence: fence,
        followRedirects: false,
      );
      if (data is! Map || data['ok'] != true) return left(_revokeUnknown);
      final revoked = data['revokedSessions'];
      if (revoked is! int || revoked < 0) return left(_revokeUnknown);
      return right(revoked);
    } on NowaveApiException catch (error) {
      return left(_revokeFailure(error));
    } catch (_) {
      return left(_revokeUnknown);
    }
  }

  /// Shared mapping for the two revocation endpoints.
  ///
  /// A 404 on the collection endpoint is an old deployment (the list proves the
  /// route existed for reads only), and 405 is the same story; neither is a
  /// state the caller can fix by trying again.
  Failure _revokeFailure(NowaveApiException error) {
    if (error.code == 'SESSION_CHANGED') {
      return const Failure(
        '登录账户已变更；本次操作已作废，请重新打开本页',
        kind: FailureKind.auth,
        code: 'auth.sessionChanged',
      );
    }
    if (error.statusCode == 403) return Failure.permission();
    if (error.statusCode == 401) {
      return const Failure(
        '登录已过期，请重新登录',
        kind: FailureKind.auth,
        code: 'server.UNAUTHENTICATED',
      );
    }
    if (error.statusCode == 404 || error.statusCode == 405) {
      return const Failure(
        '此服务器暂不支持结束登录会话',
        kind: FailureKind.server,
        code: 'sessions.revokeUnavailable',
      );
    }
    if (error.statusCode == 429) {
      return const Failure(
        '操作过于频繁，请稍后再试',
        kind: FailureKind.server,
        code: 'server.RATE_LIMITED',
      );
    }
    if (error.statusCode == 400) {
      return const Failure(
        '服务器拒绝了结束会话的请求',
        kind: FailureKind.validation,
        code: 'sessions.revokeRejected',
      );
    }
    // A later 5xx, a proxy or a dropped connection may hide a completed
    // revocation: the session may already be gone.
    return _revokeUnknown;
  }

  Failure _parseFailure() => const Failure(
    '数据格式错误，请更新应用后重试',
    kind: FailureKind.validation,
    code: 'client.parse',
  );

  List<AccountSession> _parseSessions(dynamic data) {
    if (data is! Map<String, dynamic> || data['sessions'] is! List) {
      throw const FormatException('Invalid session list');
    }
    final rows = data['sessions'] as List;
    // The endpoint promises at most 50. Reject a broken contract rather
    // than quietly presenting a truncated list as the server response.
    if (rows.length > 50) throw const FormatException('Invalid session list');
    final sessions = <AccountSession>[];
    var currentCount = 0;
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          row['sessionId'] is! String ||
          (row['sessionId'] as String).isEmpty ||
          row['current'] is! bool) {
        throw const FormatException('Invalid session list');
      }
      final current = row['current'] as bool;
      if (current && ++currentCount > 1) {
        throw const FormatException('Invalid session list');
      }
      final rawLastUsed = row['lastUsedAt'];
      sessions.add(
        AccountSession(
          id: row['sessionId'] as String,
          createdAt: _parseTime(row['createdAt']),
          lastRefreshedAt: rawLastUsed == null ? null : _parseTime(rawLastUsed),
          expiresAt: _parseTime(row['expiresAt']),
          current: current,
        ),
      );
    }
    return List.unmodifiable(sessions);
  }

  static final RegExp _timeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$');

  DateTime _parseTime(dynamic value) {
    // no-wave serializes instants with an offset (normally Z). Never
    // interpret a malformed zone-less server time as this device's timezone.
    final parsed = value is String && _timeZone.hasMatch(value)
        ? DateTime.tryParse(value)
        : null;
    if (parsed == null) throw const FormatException('Invalid session time');
    return parsed;
  }
}

const _invalidSession = Failure(
  '会话标识无效，请刷新列表后重试',
  kind: FailureKind.validation,
  code: 'sessions.invalidSession',
);
const _revokeUnknown = Failure(
  '无法确认结果：该设备可能已经退出登录。请刷新列表核对，不要重复操作',
  kind: FailureKind.unknown,
  code: 'sessions.revokeUnknown',
);
