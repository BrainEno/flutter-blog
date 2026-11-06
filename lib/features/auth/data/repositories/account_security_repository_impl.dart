import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/domain/email_rules.dart';
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
    Future<void> Function(String email)? rememberEmail,
  }) : _client = client,
       _session = session,
       _connectionChecker = connectionChecker,
       _rememberEmailAddress = rememberEmail;

  final NowaveApiClient _client;
  final NowaveViewerAuthenticator _session;
  final ConnectionChecker _connectionChecker;

  /// How a changed address reaches local storage; see [rememberEmail].
  final Future<void> Function(String email)? _rememberEmailAddress;

  bool _inFlight = false;

  @override
  Future<Either<Failure, String>> changeEmail({
    required String expectedUserId,
    required int expectedSessionGeneration,
    required String currentPassword,
    required String newEmail,
  }) async {
    if (_inFlight) return left(_emailInProgress);
    if (validateCurrentPassword(currentPassword) != null ||
        validateEmailAddress(newEmail) != null) {
      return left(_emailInvalidInput);
    }
    final email = normalizeEmailAddress(newEmail);
    _inFlight = true;
    try {
      bool sameSession() =>
          expectedUserId.isNotEmpty &&
          _session.activeUserId == expectedUserId &&
          _session.sessionGeneration == expectedSessionGeneration &&
          (_session.accessToken?.isNotEmpty ?? false);

      if (!sameSession()) return left(_sessionChanged);

      // The same shape of preflight as the password form: a safe read may
      // refresh the access token, and the PUT itself must never be replayed -
      // a 401 there can mean "wrong password", not "expired token".
      try {
        if (!await _connectionChecker.isConnected) {
          return left(Failure.networkOffline());
        }
        if (!sameSession()) return left(_sessionChanged);
        final me = await _client.getJsonForViewer(
          '/me',
          expectedUserId: expectedUserId,
        );
        if (!sameSession()) return left(_sessionChanged);
        if (me is! Map || me['id'] != expectedUserId) {
          return left(_emailIdentityUnconfirmed);
        }
      } catch (error) {
        // Nothing was written yet, so the cause can be dropped entirely.
        return left(mapErrorToFailure(error).forPresentation());
      }

      try {
        final data = await _client.putJsonForViewerOnce(
          '/me/email',
          {'password': currentPassword, 'email': email},
          expectedUserId: expectedUserId,
          expectedSessionGeneration: expectedSessionGeneration,
        );
        if (!sameSession()) return left(_sessionChanged);
        if (data is! Map || data['ok'] != true) {
          // A 2xx this build cannot read may still have committed the change.
          return left(_emailOutcomeUnknown);
        }
        // The server normalizes the address; show what it stored, not what was
        // typed.
        final stored = data['email'];
        final address = stored is String && stored.isNotEmpty ? stored : email;
        await _rememberEmail(address);
        return right(address);
      } on NowaveApiException catch (error) {
        if (error.code == 'SESSION_CHANGED') return left(_sessionChanged);
        // 409 with this code is the one conflict a reader can act on: the
        // address belongs to another account.
        if (error.code == 'EMAIL_TAKEN') return left(_emailTaken);
        if (error.statusCode == HttpStatus.unauthorized) {
          return left(_emailRejected);
        }
        if (error.statusCode == HttpStatus.tooManyRequests) {
          return left(_rateLimited);
        }
        if (error.statusCode == HttpStatus.notFound ||
            error.statusCode == HttpStatus.methodNotAllowed) {
          return left(_emailUnsupported);
        }
        if (error.statusCode == HttpStatus.badRequest) {
          return left(_emailInvalidInput);
        }
        if (error.statusCode == HttpStatus.forbidden) {
          return left(Failure.permission());
        }
        // A later 5xx, or a proxy in between, can hide a committed write.
        return left(_emailOutcomeUnknown);
      } catch (_) {
        // Includes connection loss and timeouts after the request was sent.
        return left(_emailOutcomeUnknown);
      }
    } finally {
      _inFlight = false;
    }
  }

  /// Records the address the server now holds, so an offline restart does not
  /// keep showing the previous one.
  ///
  /// Best effort on purpose: the write has already succeeded, and failing to
  /// note it locally must not be reported as an uncertain change.
  Future<void> _rememberEmail(String email) async {
    final remember = _rememberEmailAddress;
    if (remember == null) return;
    try {
      await remember(email);
    } catch (_) {
      // Nothing actionable: the next `GET /me` on a connected device corrects
      // the local copy anyway.
    }
  }

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

const _emailTaken = Failure(
  '该邮箱已被其他账户使用，请换一个地址',
  kind: FailureKind.validation,
  code: 'account.emailTaken',
);
const _emailRejected = Failure(
  '当前密码可能不正确，或登录已失效；请核对密码或重新登录',
  kind: FailureKind.auth,
  code: 'account.emailRejected',
);
const _emailIdentityUnconfirmed = Failure(
  '无法确认当前账户，本次未提交改邮箱请求；请重新登录后重试',
  kind: FailureKind.auth,
  code: 'account.emailIdentityUnconfirmed',
);
const _emailOutcomeUnknown = Failure(
  '无法确认修改结果：邮箱可能已变更。请稍后打开「修改邮箱」核对当前地址，勿立即重复提交。',
  kind: FailureKind.unknown,
  code: 'account.emailOutcomeUnknown',
);
const _emailUnsupported = Failure(
  '当前服务器不支持修改邮箱，请联系服务提供方',
  kind: FailureKind.server,
  code: 'account.emailUnsupported',
);
const _emailInvalidInput = Failure(
  '邮箱或当前密码不符合要求，请检查后重试',
  kind: FailureKind.validation,
  code: 'account.emailInvalid',
);
const _emailInProgress = Failure(
  '已有账户安全修改正在处理，请等待结果',
  kind: FailureKind.validation,
  code: 'account.changeInProgress',
);
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
  '无法确认修改结果：密码可能已更改，其他设备仍可能保持登录。请先用新密码登录确认，勿立即重复提交',
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
