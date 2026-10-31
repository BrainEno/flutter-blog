import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:fpdart/fpdart.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final ConnectionChecker connectionChecker;

  /// Last confirmed profile, so an offline restore still shows a name
  /// and an avatar (issue #50). Display-layer fallback only.
  final ProfileCacheStore profileCache;

  /// Device-local history is cleared for the signing-out account (#22).
  /// Required so the production composition root cannot silently omit it.
  final ReadingHistoryStore readingHistoryStore;

  const AuthRepositoryImpl(
    this.remoteDataSource,
    this.connectionChecker,
    this.profileCache, {
    required this.readingHistoryStore,
  });

  @override
  Future<Either<Failure, User>> currentUser() async {
    try {
      final generation = remoteDataSource.sessionGeneration;
      final connected = await connectionChecker.isConnected;
      var stale = _staleSessionFailure(generation);
      if (stale != null) return left(stale);

      if (!connected) {
        final session = remoteDataSource.currentSession;
        if (session == null) {
          return left(
            Failure(
              '请登录账户',
              kind: FailureKind.auth,
              code: 'auth.rejected',
              l10nKey: 'auth.required',
            ),
          );
        }

        // An unresolved identity must never inherit the old global cache.
        final cached = session.userId.trim().isEmpty
            ? null
            : await _readCachedProfile(session.userId);
        stale = _staleSessionFailure(generation);
        if (stale != null) return left(stale);
        return right(
          UserModel(
            id: session.userId,
            email: session.email,
            name: cached?.displayName ?? '',
            avatarUrl: cached?.avatarUrl ?? '',
            website: cached?.website ?? '',
            updatedAt: DateTime.now(),
          ),
        );
      }

      final userModel = await remoteDataSource.getCurrentUserData();
      stale = _staleSessionFailure(generation);
      if (stale != null) return left(stale);
      if (userModel == null || remoteDataSource.currentSession == null) {
        return left(_expiredSessionFailure());
      }
      final session = remoteDataSource.currentSession!;
      if (session.userId.isNotEmpty &&
          (session.userId != userModel.id ||
              session.email != userModel.email)) {
        return left(_changedSessionFailure());
      }
      if (session.userId.isNotEmpty) await _writeCachedProfile(userModel);
      stale = _staleSessionFailure(generation);
      if (stale != null) return left(stale);
      return right(userModel);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, User>> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      final user = await remoteDataSource.loginWithEmailPassword(
        email: email,
        password: password,
      );
      final generation = remoteDataSource.sessionGeneration;
      if (!_matchesCurrentSession(user)) return left(_changedSessionFailure());
      await _writeCachedProfile(user);
      final stale = _staleSessionFailure(generation);
      if (stale != null) return left(stale);
      return right(user);
    } on NowaveApiException catch (e) {
      return left(_loginFailure(e));
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, User>> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure.networkOffline());
      }
      // The backend signs the user in immediately: there is no e-mail
      // confirmation step.
      final user = await remoteDataSource.signUpWithEmailPassword(
        name: name,
        email: email,
        password: password,
      );
      final generation = remoteDataSource.sessionGeneration;
      if (!_matchesCurrentSession(user)) return left(_changedSessionFailure());
      await _writeCachedProfile(user);
      final stale = _staleSessionFailure(generation);
      if (stale != null) return left(stale);
      return right(user);
    } on NowaveApiException catch (e) {
      return left(_signUpFailure(e));
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    // No connectivity gate: the local session must be droppable even when
    // offline, otherwise a user could never sign out on a plane. The data
    // source treats server-side revocation as best-effort and clears the
    // local session regardless.
    // The reading history belongs to the account that is signing out and
    // must not leak into the next account on a shared device.
    final signingOutUserId = remoteDataSource.currentSession?.userId;
    try {
      await remoteDataSource.logout();
      // Delete only the account captured before the async logout. A different
      // account can sign in while cleanup is in flight.
      await _clearCachedProfile(signingOutUserId);
      await _clearReadingHistory(signingOutUserId);
      return right(null);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  /// Best-effort like the profile cache: a storage hiccup is logged and
  /// swallowed, never surfaced as a logout failure.
  Future<void> _clearReadingHistory(String? userId) async {
    if (userId == null || userId.trim().isEmpty) return;
    try {
      await readingHistoryStore.clear(userId: userId);
    } catch (e, stackTrace) {
      AppLogger.error(
        'clearing the reading history failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Failure _expiredSessionFailure() => Failure(
    '登录状态已失效，请重新登录',
    kind: FailureKind.auth,
    code: 'auth.rejected',
    l10nKey: 'auth.sessionExpired',
  );

  Failure _changedSessionFailure() => Failure(
    '登录账户已变更，请重试',
    kind: FailureKind.auth,
    code: 'auth.sessionChanged',
  );

  Failure? _staleSessionFailure(int expectedGeneration) {
    if (remoteDataSource.sessionGeneration == expectedGeneration) return null;
    return remoteDataSource.currentSession == null
        ? _expiredSessionFailure()
        : _changedSessionFailure();
  }

  bool _matchesCurrentSession(User user) {
    final session = remoteDataSource.currentSession;
    return session != null &&
        session.userId.isNotEmpty &&
        session.userId == user.id &&
        session.email == user.email;
  }

  /// Cache reads/writes are display conveniences: a storage hiccup is
  /// logged and swallowed, never surfaced as a login failure.
  Future<CachedProfile?> _readCachedProfile(String userId) async {
    try {
      return await profileCache.read(userId: userId);
    } catch (e, stackTrace) {
      AppLogger.error(
        'reading the cached profile failed',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _writeCachedProfile(UserModel user) async {
    if (user.id.trim().isEmpty) return;
    try {
      await profileCache.write(
        userId: user.id,
        profile: CachedProfile(
          displayName: user.name,
          avatarUrl: user.avatarUrl,
          website: user.website,
          updatedAt: user.updatedAt,
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'writing the cached profile failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _clearCachedProfile(String? userId) async {
    if (userId == null || userId.trim().isEmpty) return;
    try {
      await profileCache.clear(userId: userId);
    } catch (e, stackTrace) {
      AppLogger.error(
        'clearing the cached profile failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Wrong credentials come back as a plain 401 UNAUTHENTICATED; the
  /// generic mapping would misleadingly say the login "expired".
  Failure _loginFailure(NowaveApiException e) {
    switch (e.code) {
      case 'UNAUTHENTICATED':
        return Failure(
          '邮箱或密码不正确',
          kind: FailureKind.auth,
          code: 'auth.rejected',
          l10nKey: 'auth.invalidCredentials',
          cause: e,
        );
      case 'RATE_LIMITED':
        return Failure(
          '尝试次数过多，请稍后再试',
          kind: FailureKind.auth,
          code: 'auth.rateLimited',
          cause: e,
        );
      case 'BAD_USER_INPUT':
        return Failure(
          '邮箱或密码格式不正确',
          kind: FailureKind.validation,
          code: 'auth.emailPasswordFormat',
          cause: e,
        );
      default:
        return mapToServerException(e).toFailure();
    }
  }

  Failure _signUpFailure(NowaveApiException e) {
    switch (e.code) {
      case 'CONFLICT':
        return Failure(
          '该邮箱已被注册，请直接登录',
          kind: FailureKind.validation,
          code: 'auth.emailTaken',
          cause: e,
        );
      case 'BAD_USER_INPUT':
        return Failure(
          '注册信息不符合要求，请检查邮箱与密码（密码至少 12 位）',
          kind: FailureKind.validation,
          code: 'auth.signupBadInput',
          cause: e,
        );
      case 'RATE_LIMITED':
        return Failure(
          '注册过于频繁，请稍后再试',
          kind: FailureKind.auth,
          code: 'auth.signupRateLimited',
          cause: e,
        );
      default:
        return mapToServerException(e).toFailure();
    }
  }
}
