import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements UserRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  late MockRemote remote;
  late MockConnection connection;
  late UserRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    repository = UserRepositoryImpl(remote, connection);
  });

  group('resetPassword (changePassword)', () {
    test('a failing password change surfaces as a failure, not a fake '
        'success', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      // Regression for the old bug: the datasource printed the error and
      // returned normally, so the UI showed "password changed".
      when(() => remote.changePassword('new-secret')).thenThrow(
        const ServerException(
          'New password should be at least 6 characters.',
          kind: FailureKind.auth,
        ),
      );

      final result = await repository.resetPassword('new-secret');
      result.fold((failure) {
        expect(failure.kind, FailureKind.auth);
        expect(failure.message, contains('6 characters'));
      }, (_) => fail('a failed password change must not report success'));
    });

    test('unexpected datasource errors become safe failures', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.changePassword('new-secret'),
      ).thenThrow(StateError('token=secret'));

      final result = await repository.resetPassword('new-secret');
      result.fold((failure) {
        expect(failure.message, isNot(contains('secret')));
        expect(failure.kind, FailureKind.unknown);
      }, (_) => fail('expected failure'));
    });

    test('successful change returns right without any output', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.changePassword('new-secret')).thenAnswer((_) async {});

      final result = await repository.resetPassword('new-secret');
      expect(result.isRight(), isTrue);
    });

    test('offline change fails fast with a network failure', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.resetPassword('new-secret');
      result.fold(
        (failure) => expect(failure.kind, FailureKind.network),
        (_) => fail('offline change must not report success'),
      );
      verifyNever(() => remote.changePassword(any()));
    });
  });

  group('changeEmail', () {
    test('errors are mapped instead of leaking the raw exception', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => remote.changeEmail('a@b.c'),
      ).thenThrow(const ServerException('Email rate limit exceeded'));

      final result = await repository.changeEmail('a@b.c');
      result.fold(
        (failure) => expect(failure.message, 'Email rate limit exceeded'),
        (_) => fail('expected failure'),
      );
    });

    test('offline change fails fast', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);
      final result = await repository.changeEmail('a@b.c');
      expect(result.isLeft(), isTrue);
      verifyNever(() => remote.changeEmail(any()));
    });
  });

  group('editUserInfo', () {
    test(
      'unexpected errors no longer crash through - they fail safely',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.getUserById('u1')).thenThrow(StateError('private'));

        final result = await repository.editUserInfo(
          userId: 'u1',
          name: 'n',
          email: 'a@b.c',
          website: '',
          avatar: File('/nonexistent.png'),
        );
        result.fold(
          (failure) => expect(failure.message, isNot(contains('private'))),
          (_) => fail('expected failure'),
        );
      },
    );
  });
}
