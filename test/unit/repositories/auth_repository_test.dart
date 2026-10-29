import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

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
  late AuthRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    repository = AuthRepositoryImpl(remote, connection);
  });

  group('currentUser (offline session restore)', () {
    test('a persisted session restores a minimal user without network',
        () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentSession).thenReturn(_session());

      final result = await repository.currentUser();

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('expected a restored user'), (user) {
        expect(user.id, 'u1');
        expect(user.email, 'user@example.invalid');
      });
    });

    test('no session offline means not logged in', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentSession).thenReturn(null);

      final result = await repository.currentUser();
      expect(result.isLeft(), isTrue);
    });
  });

  group('currentUser (online)', () {
    test('a session that cannot be refreshed is NOT treated as logged in',
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
  });

  group('signUpWithEmailPassword', () {
    test('a successful sign-up is a signed-in user (no confirmation step)',
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
    });

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

      result.fold(
        (failure) {
          expect(failure.message, contains('邮箱或密码不正确'));
          expect(failure.kind, FailureKind.auth);
        },
        (_) => fail('expected a failure'),
      );
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
}
