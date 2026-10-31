import 'package:belog/core/error/exceptions.dart';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/data/models/user_model.dart';

/// Authentication against the no-wave backend.
///
/// The backend supports password reset and e-mail verification, but this
/// client has not integrated those flows (see the migration document, G2).
/// The current `GET /me` can also return an e-mail and verification status;
/// this client reads only the id and uses the locally cached sign-in e-mail.
abstract interface class AuthRemoteDataSource {
  /// The locally persisted session, without any network traffic.
  NowaveSessionData? get currentSession;

  Future<UserModel> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  });

  Future<UserModel> loginWithEmailPassword({
    required String email,
    required String password,
  });

  /// The signed-in user, or null when there is no usable session.
  Future<UserModel?> getCurrentUserData();

  /// Revokes the session family server-side and drops the local session.
  Future<void> logout();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final NowaveApiClient client;
  final NowaveSessionManager sessionManager;

  AuthRemoteDataSourceImpl(this.client, this.sessionManager);

  @override
  NowaveSessionData? get currentSession => sessionManager.currentSession;

  @override
  Future<UserModel> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    // Registration is immediate: the backend returns a session without an
    // e-mail confirmation step, so the user is signed in right away.
    final tokens = await _exchangeTokens(
      () => client.postJson('/auth/register', {
        'email': email,
        'password': password,
      }, authenticate: false),
    );
    await sessionManager.adoptSession(tokens, email: email);
    try {
      await _resolveUserIdentity();
      // The backend has no name field at registration: the display name is
      // written to the profile right after the account exists.
      await client.putJson('/me/profile', {'displayName': name});
    } catch (e, stackTrace) {
      // The account exists and the session is valid; a failed profile
      // write must not fail the whole sign-up. The name can be edited
      // later in the profile page - but the failure must leave a trace,
      // or support has nothing to work with.
      AppLogger.error(
        'writing the display name during sign-up failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
    final user = await _loadCurrentUser(email: email);
    sessionManager.notifySignedIn();
    return user;
  }

  @override
  Future<UserModel> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final tokens = await _exchangeTokens(
      () => client.postJson('/auth/login', {
        'email': email,
        'password': password,
      }, authenticate: false),
    );
    await sessionManager.adoptSession(tokens, email: email);
    await _resolveUserIdentity();
    final user = await _loadCurrentUser(email: email);
    sessionManager.notifySignedIn();
    return user;
  }

  @override
  Future<UserModel?> getCurrentUserData() async {
    final email = currentSession?.email ?? '';
    if (sessionManager.accessToken == null) {
      return null;
    }
    try {
      return await _loadCurrentUser(email: email);
    } on NowaveApiException catch (e) {
      if (e.statusCode == HttpStatus.unauthorized) {
        // The session could not be refreshed: not signed in.
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    final session = sessionManager.currentSession;
    final rotationInFlight = sessionManager.refreshInFlight;
    // Stop local work immediately. Revoke with captured credentials only: a
    // later sign-in must never be used to retry the old account's logout.
    await sessionManager.clear();
    if (session == null || session.accessToken.isEmpty) return;
    Future<void> revoke(String token) async {
      await client.deleteJson(
        '/me/session',
        authenticate: false,
        extraHeaders: {'authorization': 'Bearer $token'},
      );
    }

    try {
      try {
        await revoke(session.accessToken);
      } on NowaveApiException catch (error) {
        if (error.statusCode != HttpStatus.unauthorized ||
            rotationInFlight ||
            session.refreshToken.isEmpty ||
            !session.refreshExpiresAt.isAfter(DateTime.now())) {
          rethrow;
        }
        // An expired access token can still revoke its own session family.
        // Never race an existing rotation: reuse revokes the token family.
        final data = await client.postJson('/auth/refresh', {
          'refreshToken': session.refreshToken,
        }, authenticate: false);
        if (data is! Map)
          throw const FormatException('Invalid token response.');
        final pair = NowaveTokenPair.fromDataMap(data.cast<String, dynamic>());
        if (pair.accessToken.isEmpty)
          throw const FormatException('Missing access token.');
        await revoke(pair.accessToken);
      }
    } catch (e) {
      // Server revocation is best effort even when the device is offline.
      AppLogger.debug('session revocation failed during logout: $e');
    }
  }

  Future<NowaveTokenPair> _exchangeTokens(
    Future<dynamic> Function() call,
  ) async {
    final data = await call();
    if (data is! Map) {
      throw ServerException('登录响应格式错误', code: 'auth.parse', cause: data);
    }
    return NowaveTokenPair.fromDataMap(data.cast<String, dynamic>());
  }

  /// Fetches the user id via `GET /me` and records it on the session.
  Future<void> _resolveUserIdentity() async {
    final data = await client.getJson('/me');
    final id = (data as Map?)?['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const ServerException('登录响应缺少用户信息', code: 'auth.parse.missingUser');
    }
    await sessionManager.updateUserId(id);
  }

  Future<UserModel> _loadCurrentUser({required String email}) async {
    final profile = await client.getJson('/me/profile');
    if (profile is! Map) {
      throw ServerException(
        '个人资料响应格式错误',
        code: 'profile.parse',
        cause: profile,
      );
    }
    return UserModel.fromNowaveProfile(
      profile.cast<String, dynamic>(),
      email: email,
    );
  }
}
