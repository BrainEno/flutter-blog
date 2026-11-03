import 'package:belog/core/error/exceptions.dart';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/domain/auth_intent_gate.dart';

/// Authentication against the no-wave backend.
///
/// The backend supports password reset and e-mail verification, but this
/// client has not integrated those flows (see the migration document, G2).
/// The current `GET /me` can also return an e-mail and verification status;
/// this client reads only the id and uses the locally cached sign-in e-mail.
abstract interface class AuthRemoteDataSource {
  /// The locally persisted session, without any network traffic.
  NowaveSessionData? get currentSession;

  /// Changes when a session is adopted, restored or cleared, not on refresh.
  int get sessionGeneration;

  /// [intent] is the id from [AuthIntentGate.begin]. A response whose intent
  /// is no longer the newest must not adopt its session.
  Future<UserModel> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
    int? intent,
  });

  Future<UserModel> loginWithEmailPassword({
    required String email,
    required String password,
    int? intent,
  });

  /// The signed-in user, or null when there is no usable session.
  Future<UserModel?> getCurrentUserData();

  /// Revokes the session family server-side and drops the local session.
  Future<void> logout();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final NowaveApiClient client;
  final NowaveSessionManager sessionManager;

  /// Orders authentication intents so a slow, older response cannot replace
  /// the account a newer attempt adopted (issue #99).
  final AuthIntentGate intentGate;

  AuthRemoteDataSourceImpl(
    this.client,
    this.sessionManager, {
    AuthIntentGate? intentGate,
  }) : intentGate = intentGate ?? AuthIntentGate();

  @override
  NowaveSessionData? get currentSession => sessionManager.currentSession;

  @override
  int get sessionGeneration => sessionManager.sessionGeneration;

  @override
  Future<UserModel> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
    int? intent,
  }) async {
    // Registration is immediate: the backend returns a session without an
    // e-mail confirmation step, so the user is signed in right away.
    final tokens = await _exchangeTokens(
      () => client.postJson('/auth/register', {
        'email': email,
        'password': password,
      }, authenticate: false),
    );
    // A newer sign-in/sign-up may have started while these tokens were in
    // flight; its session must not be replaced by this older attempt.
    _requireIntent(intent);
    // Capture the generation immediately: adoptSession changes it before
    // awaiting persistence, during which another account may be adopted.
    final adopting = sessionManager.adoptSession(tokens, email: email);
    final generation = sessionManager.sessionGeneration;
    await adopting;
    _requireSession(generation, intent);
    try {
      await _resolveUserIdentity(generation);
      _requireSession(generation, intent);
      // The backend has no name field at registration: the display name is
      // written to the profile right after the account exists.
      await client.putJson('/me/profile', {'displayName': name});
      _requireSession(generation, intent);
    } catch (e, stackTrace) {
      // A replacement session is not a recoverable profile-write failure.
      _requireSession(generation, intent);
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
    _requireSession(generation, intent);
    final user = await _loadCurrentUser(email: email);
    await _recordProfileIdentityIfMissing(user, generation);
    _requireSession(generation, intent);
    sessionManager.notifySignedIn();
    return user;
  }

  @override
  Future<UserModel> loginWithEmailPassword({
    required String email,
    required String password,
    int? intent,
  }) async {
    final tokens = await _exchangeTokens(
      () => client.postJson('/auth/login', {
        'email': email,
        'password': password,
      }, authenticate: false),
    );
    // A newer intent owns the session: drop these tokens unsaved.
    _requireIntent(intent);
    final adopting = sessionManager.adoptSession(tokens, email: email);
    final generation = sessionManager.sessionGeneration;
    await adopting;
    _requireSession(generation, intent);
    await _resolveUserIdentity(generation);
    final user = await _loadCurrentUser(email: email);
    _requireSession(generation, intent);
    sessionManager.notifySignedIn();
    return user;
  }

  @override
  Future<UserModel?> getCurrentUserData() async {
    final generation = sessionManager.sessionGeneration;
    final email = currentSession?.email ?? '';
    if (sessionManager.accessToken == null) {
      return null;
    }
    try {
      final user = await _loadCurrentUser(email: email);
      await _recordProfileIdentityIfMissing(user, generation);
      return user;
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
    final generation = sessionManager.sessionGeneration;
    void ensureSameSession(int expected) {
      if (sessionManager.sessionGeneration != expected &&
          sessionManager.currentSession != null) {
        throw const NowaveApiException(
          statusCode: HttpStatus.conflict,
          code: 'SESSION_CHANGED',
          message: 'Session changed while signing out.',
        );
      }
    }

    try {
      // Revokes the whole session family (access and refresh tokens).
      await client.deleteJson('/me/session');
    } catch (e) {
      ensureSameSession(generation);
      // Best-effort server-side revocation. Never print raw error details.
      AppLogger.debug(
        'session revocation failed during logout (${e.runtimeType})',
      );
    }
    ensureSameSession(generation);
    final clearing = sessionManager.clear();
    final clearedGeneration = sessionManager.sessionGeneration;
    await clearing;
    // A new login may have arrived while the platform store was clearing.
    ensureSameSession(clearedGeneration);
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

  /// Throws when [intent] is no longer the newest authentication intent.
  void _requireIntent(int? intent) {
    if (intentGate.allows(intent)) return;
    throw const NowaveApiException(
      statusCode: HttpStatus.conflict,
      code: 'SESSION_SUPERSEDED',
      message: 'A newer authentication intent superseded this one.',
    );
  }

  /// Both fences at once: no newer intent, and no replaced session.
  void _requireSession(int generation, int? intent) {
    _requireIntent(intent);
    _requireGeneration(generation);
  }

  void _requireGeneration(int generation) {
    if (sessionManager.sessionGeneration != generation) {
      throw const NowaveApiException(
        statusCode: HttpStatus.conflict,
        code: 'SESSION_CHANGED',
        message: 'Session changed during authentication.',
      );
    }
  }

  /// Fetches the user id via `GET /me` and records it only on that session.
  Future<void> _resolveUserIdentity(int generation) async {
    _requireGeneration(generation);
    final data = await client.getJson('/me');
    _requireGeneration(generation);
    final id = (data as Map?)?['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const ServerException('登录响应缺少用户信息', code: 'auth.parse.missingUser');
    }
    await sessionManager.updateUserId(id);
    _requireGeneration(generation);
  }

  /// A successfully fetched `/me/profile` also supplies the server's user id.
  /// It can recover sessions where the initial `/me` lookup was interrupted.
  Future<void> _recordProfileIdentityIfMissing(
    UserModel user,
    int generation,
  ) async {
    _requireGeneration(generation);
    if (sessionManager.currentSession?.userId.isEmpty == true &&
        user.id.isNotEmpty) {
      await sessionManager.updateUserId(user.id);
      _requireGeneration(generation);
    }
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
