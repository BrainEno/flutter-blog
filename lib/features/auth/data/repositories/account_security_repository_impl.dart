import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The singleton serializes sensitive changes even across multiple screens.
/// Neither passwords nor raw server/transport errors are retained in failures.
class AccountSecurityRepositoryImpl implements AccountSecurityRepository {
  AccountSecurityRepositoryImpl({
    required NowaveApiClient client,
    required NowaveViewerAuthenticator session,
    required ConnectionChecker connectionChecker,
  }) : _client = client,
       _session = session,
       _connectionChecker = connectionChecker;

  final NowaveApiClient _client;
  final NowaveViewerAuthenticator _session;
  final ConnectionChecker _connectionChecker;
  bool _inFlight = false;

  @override
  Future<Either<Failure, void>> changePassword({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_inFlight) return left(_inProgress);
    if (validateCurrentPassword(currentPassword) != null ||
        validateNewPassword(newPassword) != null) {
      return left(_invalidInput);
    }
    _inFlight = true;
    try {
      bool sameSession() =>
          expectedUserId.isNotEmpty &&
          _session.activeUserId == expectedUserId &&
          _session.sessionGeneration == expectedSessionGeneration &&
          (_session.accessToken?.isNotEmpty ?? false);

      if (!sameSession()) return left(_sessionChanged);
      try {
        if (!await _connectionChecker.isConnected) {
          return left(Failure.networkOffline());
        }
        if (!sameSession()) return left(_sessionChanged);

        // A safe read can refresh the token before the sensitive write. Check
        // the server identity as well as the local fence; a 401 from the PUT
        // remains ambiguous even after this preflight.
        final me = await _client.getJsonForViewer(
          '/me',
          expectedUserId: expectedUserId,
        );
        if (!sameSession()) return left(_sessionChanged);
        if (me is! Map || me['id'] != expectedUserId) {
          return left(_identityUnconfirmed);
        }
      } catch (error) {
        // No password-changing request has been sent yet. Drop diagnostic
        // causes rather than keeping an untrusted response or exception.
        return left(mapErrorToFailure(error).forPresentation());
      }

      try {
        final data = await _client.putJsonForViewerOnce(
          '/me/password',
          {'currentPassword': currentPassword, 'newPassword': newPassword},
          expectedUserId: expectedUserId,
          expectedSessionGeneration: expectedSessionGeneration,
        );
        if (!sameSession()) return left(_sessionChanged);
        if (data is Map && data['ok'] == true) return right(null);
        // A malformed 2xx can arrive after the server committed the change.
        return left(_outcomeUnknown);
      } on NowaveApiException catch (error) {
        if (error.code == 'SESSION_CHANGED') return left(_sessionChanged);
        if (error.statusCode == HttpStatus.unauthorized) {
          return left(_credentialOrSessionRejected);
        }
        if (error.statusCode == HttpStatus.tooManyRequests) {
          return left(_rateLimited);
        }
        if (error.statusCode == HttpStatus.notFound ||
            error.statusCode == HttpStatus.methodNotAllowed) {
          return left(_unsupported);
        }
        if (error.statusCode == HttpStatus.badRequest) {
          return left(_invalidInput);
        }
        if (error.statusCode == HttpStatus.forbidden) {
          return left(Failure.permission());
        }
        // The backend can change the password before a later server error,
        // and a proxy or malformed response can hide a completed write.
        return left(_outcomeUnknown);
      } catch (_) {
        // Includes connection loss, timeout, bad payload and unexpected
        // failures: the request might already have reached the server.
        return left(_outcomeUnknown);
      }
    } finally {
      _inFlight = false;
    }
  }
}

const _sessionChanged = Failure(
  '登录账户已变更；操作可能已针对原账户完成，请先确认',
  kind: FailureKind.auth,
  code: 'auth.sessionChanged',
);
const _credentialOrSessionRejected = Failure(
  '当前密码可能不正确，或登录已失效；请核对密码或重新登录',
  kind: FailureKind.auth,
  code: 'auth.passwordRejected',
);
const _identityUnconfirmed = Failure(
  '无法确认当前账户，本次未提交改密请求；请重新登录后重试',
  kind: FailureKind.auth,
  code: 'auth.passwordIdentityUnconfirmed',
);
const _outcomeUnknown = Failure(
  '无法确认修改结果：密码或会话可能已改变。请先用新密码登录确认，勿立即重复提交',
  kind: FailureKind.unknown,
  code: 'auth.passwordOutcomeUnknown',
);
const _unsupported = Failure(
  '当前服务器不支持修改密码，请联系服务提供方',
  kind: FailureKind.server,
  code: 'auth.passwordUnsupported',
);
const _rateLimited = Failure(
  '尝试次数过多，请稍后再试',
  kind: FailureKind.server,
  code: 'auth.rateLimited',
);
const _invalidInput = Failure(
  '密码不符合要求，请检查后重试',
  kind: FailureKind.validation,
  code: 'server.BAD_USER_INPUT',
);
const _inProgress = Failure(
  '已有密码修改请求正在处理，请等待结果',
  kind: FailureKind.validation,
  code: 'auth.passwordInProgress',
);
