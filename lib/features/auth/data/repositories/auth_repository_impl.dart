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

  /// Device-local reading history (issue #22). Optional so tests that do
  /// not care about it keep constructing the repository with three args.
  final ReadingHistoryStore? readingHistoryStore;

  const AuthRepositoryImpl(
    this.remoteDataSource,
    this.connectionChecker,
    this.profileCache, {
    this.readingHistoryStore,
  });

  @override
  Future<Either<Failure, User>> currentUser() async {
    try {
      if (!await (connectionChecker.isConnected)) {
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

        // Offline restore: the locally persisted session keeps the user
        // signed in with a minimal identity; the last confirmed profile
        // fills in name/avatar so the page does not look broken, and the
        // fresh profile is fetched once the network is back.
        final cached = await _readCachedProfile();
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
      if (userModel == null) {
        // No session, or the session could not be refreshed. Either way
        // the user is not logged in.
        return left(
          Failure(
            '登录状态已失效，请重新登录',
            kind: FailureKind.auth,
            code: 'auth.rejected',
            l10nKey: 'auth.sessionExpired',
          ),
        );
      }
      await _writeCachedProfile(userModel);
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
      await _writeCachedProfile(user);
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
      await _writeCachedProfile(user);
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
    final historyUserId = remoteDataSource.currentSession?.userId;
    try {
      await remoteDataSource.logout();
      // The cached profile must not leak into the next account.
      await _clearCachedProfile();
      await _clearReadingHistory(historyUserId);
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
    if (userId == null || readingHistoryStore == null) return;
    try {
      await readingHistoryStore!.clear(userId: userId);
    } catch (e, stackTrace) {
      AppLogger.error(
        'clearing the reading history failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Cache reads/writes are display conveniences: a storage hiccup is
  /// logged and swallowed, never surfaced as a login failure.
  Future<CachedProfile?> _readCachedProfile() async {
    try {
      return await profileCache.read();
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
    try {
      await profileCache.write(
        CachedProfile(
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

  Future<void> _clearCachedProfile() async {
    try {
      await profileCache.clear();
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
