import 'dart:async';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

class MockProfileCache extends Mock implements ProfileCacheStore {}

class MockReadingHistory extends Mock implements ReadingHistoryStore {}

NowaveSessionData _session({String userId = 'u1'}) => NowaveSessionData(
  userId: userId,
  email: 'user@example.invalid',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

UserModel _user({String name = '测试用户'}) => UserModel(
  id: 'u1',
  email: 'user@example.invalid',
  name: name,
  updatedAt: DateTime.utc(2024),
);

void main() {
  late MockRemote remote;
  late MockConnection connection;
  late MockProfileCache profileCache;
  late MockReadingHistory history;
  late AuthRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(
      CachedProfile(
        displayName: '',
        avatarUrl: '',
        website: '',
        updatedAt: DateTime.utc(2026),
      ),
    );
  });

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    profileCache = MockProfileCache();
    history = MockReadingHistory();
    repository = AuthRepositoryImpl(
      remote,
      connection,
      profileCache,
      readingHistoryStore: history,
    );
    when(() => remote.currentSession).thenReturn(_session());
    when(() => remote.sessionGeneration).thenReturn(1);
    when(
      () => profileCache.read(userId: any(named: 'userId')),
    ).thenAnswer((_) async => null);
    when(
      () => profileCache.write(
        userId: any(named: 'userId'),
        profile: any(named: 'profile'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => profileCache.clear(userId: any(named: 'userId')),
    ).thenAnswer((_) async {});
    when(
      () => history.clear(userId: any(named: 'userId')),
    ).thenAnswer((_) async {});
  });

  group('currentUser (offline session restore)', () {
    test(
      'a persisted session restores a minimal user without network',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => false);
        when(() => remote.currentSession).thenReturn(_session());

        final result = await repository.currentUser();

        expect(result.isRight(), isTrue);
        result.fold((_) => fail('expected a restored user'), (user) {
          expect(user.id, 'u1');
          expect(user.email, 'user@example.invalid');
        });
      },
    );

    test('no session offline means not logged in', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentSession).thenReturn(null);

      final result = await repository.currentUser();
      expect(result.isLeft(), isTrue);
    });

    test('the cached profile fills name and avatar offline (#50)', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentSession).thenReturn(_session());
      when(() => profileCache.read(userId: 'u1')).thenAnswer(
        (_) async => CachedProfile(
          displayName: '测试用户',
          avatarUrl: 'https://api.example.invalid/avatar.webp',
          website: 'https://example.invalid',
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
      );

      final result = await repository.currentUser();

      result.fold((_) => fail('expected a restored user'), (user) {
        expect(user.name, '测试用户');
        expect(user.avatarUrl, 'https://api.example.invalid/avatar.webp');
        expect(user.website, 'https://example.invalid');
      });
    });

    test('an unreadable cache degrades to the minimal identity', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentSession).thenReturn(_session());
      when(
        () => profileCache.read(userId: 'u1'),
      ).thenThrow(StateError('db locked'));

      final result = await repository.currentUser();

      result.fold((_) => fail('expected a restored user'), (user) {
        expect(user.id, 'u1');
        expect(user.name, '');
      });
    });

    test('an unresolved account never reads another profile cache', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentSession).thenReturn(_session(userId: ''));

      final result = await repository.currentUser();

      result.fold((_) => fail('expected minimal identity'), (user) {
        expect(user.name, isEmpty);
        expect(user.avatarUrl, isEmpty);
      });
      verifyNever(() => profileCache.read(userId: any(named: 'userId')));
    });

    test(
      'switching accounts while cache read waits never returns old data',
      () async {
        final started = Completer<void>();
        final pending = Completer<CachedProfile?>();
        var session = _session(userId: 'u1');
        var generation = 1;
        when(() => connection.isConnected).thenAnswer((_) async => false);
        when(() => remote.currentSession).thenAnswer((_) => session);
        when(() => remote.sessionGeneration).thenAnswer((_) => generation);
        when(() => profileCache.read(userId: 'u1')).thenAnswer((_) {
          started.complete();
          return pending.future;
        });

        final result = repository.currentUser();
        await started.future;
        session = _session(userId: 'u2');
        generation++;
        pending.complete(
          CachedProfile(
            displayName: 'private old profile',
            avatarUrl: '',
            website: '',
            updatedAt: DateTime.utc(2026),
          ),
        );

        (await result).fold(
          (failure) => expect(failure.code, 'auth.sessionChanged'),
          (_) => fail('a stale profile must not be returned'),
        );
      },
    );
  });

  group('currentUser (online)', () {
    test(
      'a session that cannot be refreshed is NOT treated as logged in',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.currentSession).thenReturn(_session());
        when(() => remote.getCurrentUserData()).thenAnswer((_) async => null);

        final result = await repository.currentUser();

        result.fold((failure) {
          expect(failure.message, contains('重新登录'));
        }, (_) => fail('a dropped session must not be logged in'));
      },
    );

    test('a resolved profile restores the full user', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.currentSession).thenReturn(_session());
      when(() => remote.getCurrentUserData()).thenAnswer((_) async => _user());

      final result = await repository.currentUser();

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('expected a user'), (user) {
        expect(user.name, '测试用户');
      });
    });

    test('a successful online restore refreshes the profile cache', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.currentSession).thenReturn(_session());
      when(() => remote.getCurrentUserData()).thenAnswer((_) async => _user());

      await repository.currentUser();

      verify(
        () => profileCache.write(
          userId: 'u1',
          profile: any(named: 'profile'),
        ),
      ).called(1);
    });

    test(
      'a profile that does not match the active session is rejected',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.currentSession).thenReturn(_session(userId: 'u2'));
        when(
          () => remote.getCurrentUserData(),
        ).thenAnswer((_) async => _user());

        final result = await repository.currentUser();
        result.fold(
          (failure) => expect(failure.code, 'auth.sessionChanged'),
          (_) => fail('mismatched profile must not be returned'),
        );
        verifyNever(
          () => profileCache.write(
            userId: any(named: 'userId'),
            profile: any(named: 'profile'),
          ),
        );
      },
    );

    test(
      'a switched session during profile fetch cannot write a cache',
      () async {
        final started = Completer<void>();
        final pending = Completer<UserModel?>();
        var generation = 1;
        var session = _session(userId: 'u1');
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.sessionGeneration).thenAnswer((_) => generation);
        when(() => remote.currentSession).thenAnswer((_) => session);
        when(() => remote.getCurrentUserData()).thenAnswer((_) {
          started.complete();
          return pending.future;
        });
        final result = repository.currentUser();
        await started.future;
        generation++;
        session = _session(userId: 'u2');
        pending.complete(_user());

        (await result).fold(
          (failure) => expect(failure.code, 'auth.sessionChanged'),
          (_) => fail('a stale online response must not be returned'),
        );
        verifyNever(
          () => profileCache.write(
            userId: any(named: 'userId'),
            profile: any(named: 'profile'),
          ),
        );
      },
    );
  });

  group('signUpWithEmailPassword', () {
    test(
      'a successful sign-up is a signed-in user (no confirmation step)',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(
          () => remote.signUpWithEmailPassword(
            name: any(named: 'name'),
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => _user());

        final result = await repository.signUpWithEmailPassword(
          name: '测试用户',
          email: 'user@example.invalid',
          password: 'a-12-char-secret',
        );

        result.fold((_) => fail('expected a user'), (user) {
          expect(user.id, 'u1');
        });
      },
    );

    test('offline sign-up fails fast', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.signUpWithEmailPassword(
        name: '测试用户',
        email: 'user@example.invalid',
        password: 'a-12-char-secret',
      );

      expect(result.isLeft(), isTrue);
      verifyNever(
        () => remote.signUpWithEmailPassword(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    test('a duplicate e-mail conflict maps to a friendly message', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.signUpWithEmailPassword(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const NowaveApiException(
          statusCode: 409,
          code: 'CONFLICT',
          message: 'identity already exists',
        ),
      );

      final result = await repository.signUpWithEmailPassword(
        name: '测试用户',
        email: 'user@example.invalid',
        password: 'a-12-char-secret',
      );

      result.fold(
        (failure) => expect(failure.message, contains('已被注册')),
        (_) => fail('expected a failure'),
      );
    });
  });

  group('loginWithEmailPassword', () {
    test('a mismatched active account cannot cache a login result', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.currentSession).thenReturn(_session(userId: 'u2'));
      when(
        () => remote.loginWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => _user());

      final result = await repository.loginWithEmailPassword(
        email: 'user@example.invalid',
        password: 'secret',
      );
      result.fold(
        (failure) => expect(failure.code, 'auth.sessionChanged'),
        (_) => fail('a stale login result must not be returned'),
      );
      verifyNever(
        () => profileCache.write(
          userId: any(named: 'userId'),
          profile: any(named: 'profile'),
        ),
      );
    });

    test(
      'a switch during profile persistence invalidates the old result',
      () async {
        final started = Completer<void>();
        final pending = Completer<void>();
        var generation = 1;
        var session = _session(userId: 'u1');
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.sessionGeneration).thenAnswer((_) => generation);
        when(() => remote.currentSession).thenAnswer((_) => session);
        when(
          () => remote.loginWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => _user());
        when(
          () => profileCache.write(
            userId: 'u1',
            profile: any(named: 'profile'),
          ),
        ).thenAnswer((_) {
          started.complete();
          return pending.future;
        });

        final result = repository.loginWithEmailPassword(
          email: 'user@example.invalid',
          password: 'secret',
        );
        await started.future;
        session = _session(userId: 'u2');
        generation++;
        pending.complete();

        (await result).fold(
          (failure) => expect(failure.code, 'auth.sessionChanged'),
          (_) => fail('a replaced login must not be returned'),
        );
        verifyNever(
          () => profileCache.write(
            userId: 'u2',
            profile: any(named: 'profile'),
          ),
        );
      },
    );

    test('wrong credentials map to a credential-specific message', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.loginWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const NowaveApiException(
          statusCode: 401,
          code: 'UNAUTHENTICATED',
          message: 'authentication failed',
        ),
      );

      final result = await repository.loginWithEmailPassword(
        email: 'user@example.invalid',
        password: 'wrong',
      );

      result.fold((failure) {
        expect(failure.message, contains('邮箱或密码不正确'));
        expect(failure.kind, FailureKind.auth);
      }, (_) => fail('expected a failure'));
    });

    test('rate limiting maps to a friendly message', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.loginWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const NowaveApiException(
          statusCode: 429,
          code: 'RATE_LIMITED',
          message: 'too many attempts',
          retryAfterSeconds: 60,
        ),
      );

      final result = await repository.loginWithEmailPassword(
        email: 'user@example.invalid',
        password: 'wrong',
      );

      result.fold(
        (failure) => expect(failure.message, contains('尝试次数过多')),
        (_) => fail('expected a failure'),
      );
    });
  });

  group('logout', () {
    test('a delayed cleanup clears only the account that signed out', () async {
      final started = Completer<void>();
      final pending = Completer<void>();
      var session = _session(userId: 'u1');
      when(() => remote.currentSession).thenAnswer((_) => session);
      when(() => remote.logout()).thenAnswer((_) {
        started.complete();
        return pending.future;
      });

      final result = repository.logout();
      await started.future;
      session = _session(userId: 'u2');
      pending.complete();
      expect((await result).isRight(), isTrue);
      verify(() => profileCache.clear(userId: 'u1')).called(1);
      verify(() => history.clear(userId: 'u1')).called(1);
      verifyNever(() => profileCache.clear(userId: 'u2'));
      verifyNever(() => history.clear(userId: 'u2'));
    });

    test('a profile cleanup failure does not skip history cleanup', () async {
      when(() => remote.logout()).thenAnswer((_) async {});
      when(
        () => profileCache.clear(userId: 'u1'),
      ).thenThrow(StateError('locked'));
      expect((await repository.logout()).isRight(), isTrue);
      verify(() => history.clear(userId: 'u1')).called(1);
    });

    test('signs out even when the device is offline', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.logout()).thenAnswer((_) async {});

      final result = await repository.logout();

      expect(result.isRight(), isTrue);
      verify(() => remote.logout()).called(1);
    });

    test('online logout goes through the data source', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.logout()).thenAnswer((_) async {});

      final result = await repository.logout();

      expect(result.isRight(), isTrue);
      verify(() => remote.logout()).called(1);
      // The captured account, not a later sign-in, owns the cleanup.
      verify(() => profileCache.clear(userId: 'u1')).called(1);
      verify(() => history.clear(userId: 'u1')).called(1);
    });

    test('a data source failure surfaces as a failure', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.logout(),
      ).thenThrow(const ServerException('本地存储读写失败', kind: FailureKind.storage));

      final result = await repository.logout();

      expect(result.isLeft(), isTrue);
    });
  });
}
