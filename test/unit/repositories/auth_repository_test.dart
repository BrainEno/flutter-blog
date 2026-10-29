import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/auth/domain/entities/sign_up_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class MockRemote extends Mock implements AuthRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

sb.Session _session({String? updatedAt}) => sb.Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: sb.User(
    id: 'u1',
    appMetadata: {},
    userMetadata: {},
    aud: '',
    email: 'user@example.invalid',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: updatedAt,
  ),
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
    test('a session with a null updatedAt restores without crashing '
        '(regression: DateTime.parse on null)', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentUserSession).thenReturn(_session());

      final result = await repository.currentUser();

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('expected a restored user'), (user) {
        expect(user.id, 'u1');
        expect(user.email, 'user@example.invalid');
      });
    });

    test('an unparseable updatedAt falls back instead of throwing', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(
        () => remote.currentUserSession,
      ).thenReturn(_session(updatedAt: 'not-a-date'));

      final result = await repository.currentUser();
      expect(result.isRight(), isTrue);
    });

    test('no session offline means not logged in', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      when(() => remote.currentUserSession).thenReturn(null);

      final result = await repository.currentUser();
      expect(result.isLeft(), isTrue);
    });
  });

  group('currentUser (online)', () {
    test(
      'a valid session without a profile row is NOT treated as logged in',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.currentUserSession).thenReturn(_session());
        when(() => remote.getCurrentUserData()).thenAnswer((_) async => null);

        final result = await repository.currentUser();

        result.fold((failure) {
          expect(failure.message, contains('重新登录'));
        }, (_) => fail('an auth user without a profile must not be logged in'));
      },
    );

    test('a profile row restores the full user', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.currentUserSession).thenReturn(_session());
      when(() => remote.getCurrentUserData()).thenAnswer(
        (_) async => UserModel(
          id: 'u1',
          email: 'user@example.invalid',
          name: '测试用户',
          updatedAt: DateTime.utc(2024),
        ),
      );

      final result = await repository.currentUser();

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('expected a user'), (user) {
        expect(user.name, '测试用户');
      });
    });
  });

  group('signUpWithEmailPassword', () {
    test('forwards the pending-confirmation outcome unchanged', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.signUpWithEmailPassword(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => const SignUpOutcome(email: 'user@example.invalid'),
      );

      final result = await repository.signUpWithEmailPassword(
        name: '测试用户',
        email: 'user@example.invalid',
        password: 'secret',
      );

      result.fold((_) => fail('expected an outcome'), (outcome) {
        expect(outcome.requiresEmailConfirmation, isTrue);
      });
    });

    test('offline sign-up fails fast', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.signUpWithEmailPassword(
        name: '测试用户',
        email: 'user@example.invalid',
        password: 'secret',
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
  });
}
