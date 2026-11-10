import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/domain/email_rules.dart';
import 'package:belog/features/auth/domain/password_recovery.dart';
import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/features/auth/domain/repository/password_recovery_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Implements the anonymous no-wave recovery endpoints without ever attaching
/// the current user's session or automatically replaying a one-time token.
class PasswordRecoveryRepositoryImpl implements PasswordRecoveryRepository {
  const PasswordRecoveryRepositoryImpl({
    required NowaveApiClient client,
    required ConnectionChecker connectionChecker,
  }) : _client = client,
       _connectionChecker = connectionChecker;

  final NowaveApiClient _client;
  final ConnectionChecker _connectionChecker;

  @override
  Future<Either<Failure, void>> requestPasswordReset({
    required String email,
  }) async {
    if (validateEmailAddress(email) != null) return left(_invalidEmail);

    final connectivityFailure = await _connectivityFailure();
    if (connectivityFailure != null) return left(connectivityFailure);

    try {
      final data = await _client.postJson(
        '/auth/forgot-password',
        {'email': normalizeEmailAddress(email)},
        authenticate: false,
        followRedirects: false,
      );
      if (data is Map && data['ok'] == true) return right(null);
      // The API may have issued a token before an unexpected 2xx response was
      // produced; do not report a definite rejection or retry automatically.
      return left(_requestOutcomeUnknown);
    } on NowaveApiException catch (error) {
      return left(_requestFailure(error));
    } catch (_) {
      // A timeout or lost response may happen after the mail was accepted.
      return left(_requestOutcomeUnknown);
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword({
    required String token,
    required String password,
  }) async {
    final extractedToken = extractPasswordResetToken(token);
    if (extractedToken == null) return left(_tokenMalformed);
    if (validateNewPassword(password) != null) return left(_invalidPassword);

    final connectivityFailure = await _connectivityFailure();
    if (connectivityFailure != null) return left(connectivityFailure);

    try {
      final data = await _client.postJson(
        '/auth/reset-password',
        {'token': extractedToken, 'password': password},
        // The one-time token is the credential. Never attach a bearer token,
        // follow a redirect, or let the client replay a 401 response.
        authenticate: false,
        followRedirects: false,
      );
      if (data is Map && data['ok'] == true) return right(null);
      // A malformed success response does not prove whether the transaction
      // committed, so the UI must not encourage reuse of the same link.
      return left(_resetOutcomeUnknown);
    } on NowaveApiException catch (error) {
      return left(_resetFailure(error));
    } catch (_) {
      // Password and session revocation may already have committed.
      return left(_resetOutcomeUnknown);
    }
  }

  Future<Failure?> _connectivityFailure() async {
    try {
      return await _connectionChecker.isConnected
          ? null
          : Failure.networkOffline();
    } catch (error) {
      // This check happens before either sensitive request is sent.
      return mapErrorToFailure(error).forPresentation();
    }
  }

  Failure _requestFailure(NowaveApiException error) {
    if (error.code == 'MAIL_DISABLED') return _mailDisabled;
    if (error.code == 'RATE_LIMITED' ||
        error.statusCode == HttpStatus.tooManyRequests) {
      return _rateLimited;
    }
    if (error.code == 'BAD_USER_INPUT' ||
        error.statusCode == HttpStatus.badRequest) {
      return _invalidEmail;
    }
    if (error.code == 'NOT_FOUND' ||
        error.statusCode == HttpStatus.notFound ||
        error.statusCode == HttpStatus.methodNotAllowed) {
      return _unsupported;
    }
    if (error.statusCode >= 400 && error.statusCode < 500) {
      return _requestRejected;
    }
    // A server or proxy error can follow issuance/delivery. The response must
    // not claim that no link was sent.
    return _requestOutcomeUnknown;
  }

  Failure _resetFailure(NowaveApiException error) {
    if (error.code == 'UNAUTHENTICATED' ||
        error.statusCode == HttpStatus.unauthorized) {
      return _tokenRejected;
    }
    if (error.code == 'RATE_LIMITED' ||
        error.statusCode == HttpStatus.tooManyRequests) {
      return _rateLimited;
    }
    if (error.code == 'BAD_USER_INPUT' ||
        error.statusCode == HttpStatus.badRequest) {
      return _invalidPassword;
    }
    if (error.code == 'NOT_FOUND' ||
        error.statusCode == HttpStatus.notFound ||
        error.statusCode == HttpStatus.methodNotAllowed) {
      return _unsupported;
    }
    // Treat all other responses conservatively: the password write and
    // revocation are one transaction, but a proxy may lose its result.
    return _resetOutcomeUnknown;
  }
}

const _invalidEmail = Failure(
  '邮箱格式不正确',
  kind: FailureKind.validation,
  code: 'auth.passwordRecoveryInvalidEmail',
);
const _mailDisabled = Failure(
  '当前服务器暂不提供邮件找回',
  kind: FailureKind.server,
  code: 'auth.passwordRecoveryMailDisabled',
);
const _unsupported = Failure(
  '当前服务器暂不支持密码找回',
  kind: FailureKind.server,
  code: 'auth.passwordRecoveryUnsupported',
);
const _rateLimited = Failure(
  '请求过于频繁，请稍后再试',
  kind: FailureKind.server,
  code: 'auth.passwordRecoveryRateLimited',
);
const _requestRejected = Failure(
  '服务器没有受理这次找回请求，请稍后再试',
  kind: FailureKind.server,
  code: 'auth.passwordRecoveryRequestRejected',
);
const _requestOutcomeUnknown = Failure(
  '无法确认找回请求结果，邮件可能已经发出；请先检查邮箱再决定是否重试',
  kind: FailureKind.unknown,
  code: 'auth.passwordRecoveryRequestOutcomeUnknown',
);
const _tokenMalformed = Failure(
  '邮件链接里没有有效的重置码',
  kind: FailureKind.validation,
  code: 'auth.passwordRecoveryTokenMalformed',
);
const _invalidPassword = Failure(
  '重置码或新密码不符合要求',
  kind: FailureKind.validation,
  code: 'auth.passwordRecoveryInvalidInput',
);
const _tokenRejected = Failure(
  '重置链接无效、已使用或已过期，请重新申请',
  kind: FailureKind.auth,
  code: 'auth.passwordRecoveryTokenRejected',
);
const _resetOutcomeUnknown = Failure(
  '无法确认密码是否已重置。请先尝试用新密码登录；若失败，再申请新的重置链接，不要重复提交此链接',
  kind: FailureKind.unknown,
  code: 'auth.passwordRecoveryResetOutcomeUnknown',
);
