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

  setUpAll(() {
    registerFallbackValue(File('/nonexistent.jpg'));
    registerFallbackValue(
      UserModel(
        id: 'fallback',
        email: 'fallback@example.invalid',
        name: 'fallback',
        updatedAt: DateTime.utc(2024),
      ),
    );
  });

  setUp(() {
    remote = MockRemote();
    connection = MockConnection();
    repository = UserRepositoryImpl(remote, connection);
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
      'submits the stored identity with the new display fields',
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
          (invocation) async =>
              (invocation.positionalArguments[0] as UserModel),
        );

        await repository.editUserInfo(
          userId: 'u1',
          name: '新名字',
          website: 'https://example.invalid',
          avatar: null,
        );

        final captured =
            verify(() => remote.editUserInfo(captureAny())).captured.single
                as UserModel;
        expect(captured.id, 'u1');
        expect(captured.name, '新名字');
        expect(captured.website, 'https://example.invalid');
      },
    );

    test('a new avatar is uploaded before the profile write flips to it',
        () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      const oldAvatarUrl = 'https://api.example.invalid/api/v1/media/old';
      const newAvatarUrl = 'https://api.example.invalid/api/v1/media/new';
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
          image: any(named: 'image'),
          mimeType: 'image/jpeg',
        ),
      ).thenAnswer((_) async => newAvatarUrl);
      when(() => remote.editUserInfo(any())).thenAnswer(
        (invocation) async => (invocation.positionalArguments[0] as UserModel),
      );

      final result = await repository.editUserInfo(
        userId: 'u1',
        name: '新名字',
        website: '',
        avatar: File('/nonexistent.jpg'),
        avatarMimeType: 'image/jpeg',
      );

      expect(result.isRight(), isTrue);
      // Capture through verifyInOrder: a separate verify() afterwards
      // cannot match calls the in-order check already consumed.
      final order = verifyInOrder([
        () => remote.uploadAvatar(
              image: any(named: 'image'),
              mimeType: 'image/jpeg',
            ),
        () => remote.editUserInfo(captureAny()),
      ]);
      final captured = order.captured.single as UserModel;
      expect(captured.avatarUrl, newAvatarUrl);
    });

    test('a failed profile write surfaces as a failure', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(() => remote.getUserById('u1')).thenAnswer(
        (_) async => UserModel(
          id: 'u1',
          email: 'original@example.invalid',
          name: '旧名字',
          updatedAt: DateTime.utc(2024),
        ),
      );
      when(
        () => remote.editUserInfo(any()),
      ).thenThrow(const ServerException('rls denied'));

      final result = await repository.editUserInfo(
        userId: 'u1',
        name: '新名字',
        website: '',
        avatar: null,
      );

      expect(result.isLeft(), isTrue);
    });

    test('offline edit fails fast with a network failure', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.editUserInfo(
        userId: 'u1',
        name: '新名字',
        website: '',
        avatar: null,
      );

      result.fold(
        (failure) => expect(failure.kind, FailureKind.network),
        (_) => fail('offline edit must not report success'),
      );
      verifyNever(() => remote.getUserById(any()));
    });
  });
}
