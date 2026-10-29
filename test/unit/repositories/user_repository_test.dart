import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
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
          website: '',
          avatar: File('/nonexistent.png'),
        );
        result.fold(
          (failure) => expect(failure.message, isNot(contains('private'))),
          (_) => fail('expected failure'),
        );
      },
    );

    test(
      'never rewrites the profile e-mail: the submitted model keeps the '
      'stored address (auth e-mail changes only via the auth flow)',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        final stored = UserModel(
          id: 'u1',
          email: 'original@example.invalid',
          name: '旧名字',
          updatedAt: DateTime.utc(2024),
        );
        when(() => remote.getUserById('u1')).thenAnswer((_) async => stored);
        when(() => remote.editUserInfo(any())).thenAnswer(
          (invocation) async => (invocation.positionalArguments[0]
              as UserModel),
        );

        await repository.editUserInfo(
          userId: 'u1',
          name: '新名字',
          website: '',
          avatar: null,
        );

        final captured = verify(() => remote.editUserInfo(captureAny()))
            .captured
            .single as UserModel;
        expect(captured.email, 'original@example.invalid');
        expect(captured.name, '新名字');
      },
    );

    test(
      'avatar lifecycle: new object uploaded, old object removed only '
      'after the profile row updates',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        const oldAvatarUrl =
            'https://demo.supabase.co/storage/v1/object/public/avatars/u1';
        const newAvatarUrl =
            'https://demo.supabase.co/storage/v1/object/public/avatars/'
            'u1/1730000000000.jpg';
        final stored = UserModel(
          id: 'u1',
          email: 'original@example.invalid',
          name: '旧名字',
          avatarUrl: oldAvatarUrl,
          updatedAt: DateTime.utc(2024),
        );
        when(() => remote.getUserById('u1')).thenAnswer((_) async => stored);
        when(
          () => remote.uploadAvatar(
            userId: 'u1',
            image: any(named: 'image'),
            mimeType: 'image/jpeg',
          ),
        ).thenAnswer((_) async => newAvatarUrl);
        when(() => remote.editUserInfo(any())).thenAnswer(
          (invocation) async => (invocation.positionalArguments[0]
              as UserModel),
        );
        when(
          () => remote.removeAvatar(oldAvatarUrl),
        ).thenAnswer((_) async {});

        final result = await repository.editUserInfo(
          userId: 'u1',
          name: '新名字',
          website: '',
          avatar: File('/nonexistent.jpg'),
          avatarMimeType: 'image/jpeg',
        );

        expect(result.isRight(), isTrue);
        verifyInOrder([
          () => remote.editUserInfo(any()),
          () => remote.removeAvatar(oldAvatarUrl),
        ]);
      },
    );

    test(
      'avatar lifecycle: a failed profile update rolls back the fresh '
      'avatar and keeps the old one',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        const oldAvatarUrl =
            'https://demo.supabase.co/storage/v1/object/public/avatars/u1';
        const newAvatarUrl =
            'https://demo.supabase.co/storage/v1/object/public/avatars/'
            'u1/1730000000000.jpg';
        final stored = UserModel(
          id: 'u1',
          email: 'original@example.invalid',
          name: '旧名字',
          avatarUrl: oldAvatarUrl,
          updatedAt: DateTime.utc(2024),
        );
        when(() => remote.getUserById('u1')).thenAnswer((_) async => stored);
        when(
          () => remote.uploadAvatar(
            userId: 'u1',
            image: any(named: 'image'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer((_) async => newAvatarUrl);
        when(
          () => remote.editUserInfo(any()),
        ).thenThrow(const ServerException('rls denied'));
        when(
          () => remote.removeAvatar(newAvatarUrl),
        ).thenAnswer((_) async {});

        final result = await repository.editUserInfo(
          userId: 'u1',
          name: '新名字',
          website: '',
          avatar: File('/nonexistent.jpg'),
        );

        expect(result.isLeft(), isTrue);
        verifyNever(() => remote.removeAvatar(oldAvatarUrl));
        verify(() => remote.removeAvatar(newAvatarUrl)).called(1);
      },
    );
  });
}
