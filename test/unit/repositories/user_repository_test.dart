import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements UserRemoteDataSource {}

const NowaveSessionFence _fence = NowaveSessionFence(
  userId: 'u1',
  generation: 3,
);

class MockConnection extends Mock implements ConnectionChecker {}

void main() {
  late MockRemote remote;
  late MockConnection connection;
  late UserRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(
      ImageUpload(bytes: Uint8List(3), mimeType: 'image/jpeg'),
    );
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
    test('connection probe failures return a typed failure', () async {
      when(
        () => connection.isConnected,
      ).thenThrow(const SocketException('lost'));
      final result = await repository.editUserInfo(
        sessionFence: _fence,
        userId: 'u1',
        name: 'n',
        bio: '旧简介',
        website: '',
        avatar: null,
      );
      expect(result.getLeft().toNullable()?.kind, FailureKind.network);
      verifyNever(() => remote.getUserById(any()));
    });

    test(
      'unexpected errors no longer crash through - they fail safely',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => true);
        when(() => remote.getUserById('u1')).thenThrow(StateError('private'));

        final result = await repository.editUserInfo(
          sessionFence: _fence,
          userId: 'u1',
          name: 'n',
          bio: '旧简介',
          website: '',
          avatar: ImageUpload(bytes: Uint8List(3), mimeType: 'image/jpeg'),
        );
        result.fold(
          (failure) => expect(failure.message, isNot(contains('private'))),
          (_) => fail('expected failure'),
        );
      },
    );

    test('submits the stored identity with the new display fields', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      final stored = UserModel(
        id: 'u1',
        email: 'original@example.invalid',
        name: '旧名字',
        updatedAt: DateTime.utc(2024),
      );
      when(() => remote.getUserById('u1')).thenAnswer((_) async => stored);
      when(
        () => remote.editUserInfo(
          any(),
          sessionFence: any(named: 'sessionFence'),
        ),
      ).thenAnswer(
        (invocation) async => (invocation.positionalArguments[0] as UserModel),
      );

      await repository.editUserInfo(
        sessionFence: _fence,
        userId: 'u1',
        name: '新名字',
        bio: '新的简介',
        website: 'https://example.invalid',
        avatar: null,
      );

      final captured =
          verify(
                () => remote.editUserInfo(
                  captureAny(),
                  sessionFence: any(named: 'sessionFence'),
                ),
              ).captured.single
              as UserModel;
      expect(captured.id, 'u1');
      expect(captured.name, '新名字');
      expect(captured.bio, '新的简介');
      expect(captured.website, 'https://example.invalid');
    });

    test('the stored bio survives an unrelated name edit', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      final stored = UserModel(
        id: 'u1',
        email: 'original@example.invalid',
        name: '旧名字',
        bio: '写诗的人',
        website: 'https://example.invalid',
        updatedAt: DateTime.utc(2024),
      );
      when(() => remote.getUserById('u1')).thenAnswer((_) async => stored);
      when(
        () => remote.editUserInfo(
          any(),
          sessionFence: any(named: 'sessionFence'),
        ),
      ).thenAnswer(
        (invocation) async => (invocation.positionalArguments[0] as UserModel),
      );

      // The form forwards whatever it was pre-filled with: an untouched bio
      // and website must reach the write body unchanged, because the backend
      // stores a missing bio as ''.
      final result = await repository.editUserInfo(
        sessionFence: _fence,
        userId: 'u1',
        name: '新名字',
        bio: stored.bio,
        website: stored.website,
        avatar: null,
      );

      expect(result.isRight(), isTrue);
      final captured =
          verify(
                () => remote.editUserInfo(
                  captureAny(),
                  sessionFence: any(named: 'sessionFence'),
                ),
              ).captured.single
              as UserModel;
      expect(captured.name, '新名字');
      expect(captured.bio, '写诗的人');
      expect(captured.website, 'https://example.invalid');
    });

    test(
      'a new avatar is uploaded before the profile write flips to it',
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
            sessionFence: any(named: 'sessionFence'),
          ),
        ).thenAnswer((_) async => newAvatarUrl);
        when(
          () => remote.editUserInfo(
            any(),
            sessionFence: any(named: 'sessionFence'),
          ),
        ).thenAnswer(
          (invocation) async =>
              (invocation.positionalArguments[0] as UserModel),
        );

        final result = await repository.editUserInfo(
          sessionFence: _fence,
          userId: 'u1',
          name: '新名字',
          bio: '旧简介',
          website: '',
          avatar: ImageUpload(bytes: Uint8List(3), mimeType: 'image/jpeg'),
        );

        expect(result.isRight(), isTrue);
        // Capture through verifyInOrder: a separate verify() afterwards
        // cannot match calls the in-order check already consumed.
        final order = verifyInOrder([
          () => remote.uploadAvatar(
            image: any(named: 'image'),
            sessionFence: any(named: 'sessionFence'),
          ),
          () => remote.editUserInfo(
            captureAny(),
            sessionFence: any(named: 'sessionFence'),
          ),
        ]);
        final captured = order.last.captured.single as UserModel;
        expect(captured.avatarUrl, newAvatarUrl);
      },
    );

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
        () => remote.editUserInfo(
          any(),
          sessionFence: any(named: 'sessionFence'),
        ),
      ).thenThrow(const ServerException('rls denied'));

      final result = await repository.editUserInfo(
        sessionFence: _fence,
        userId: 'u1',
        name: '新名字',
        bio: '旧简介',
        website: '',
        avatar: null,
      );

      expect(result.isLeft(), isTrue);
    });

    test('offline edit fails fast with a network failure', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.editUserInfo(
        sessionFence: _fence,
        userId: 'u1',
        name: '新名字',
        bio: '旧简介',
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

  group('getMediaLibraryPage', () {
    test(
      'returns an offline failure without making a remote request',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => false);

        final result = await repository.getMediaLibraryPage(
          sessionFence: _fence,
          cursor: 'opaque-cursor',
        );

        result.fold(
          (failure) => expect(failure.kind, FailureKind.network),
          (_) => fail('offline media reads must fail'),
        );
        verifyNever(
          () => remote.getMediaLibraryPage(
            sessionFence: any(named: 'sessionFence'),
            cursor: any(named: 'cursor'),
          ),
        );
      },
    );

    test('forwards the original fence and opaque cursor', () async {
      when(() => connection.isConnected).thenAnswer((_) async => true);
      final page = UserMediaPage(items: const [], nextCursor: 'next-page');
      when(
        () => remote.getMediaLibraryPage(
          sessionFence: _fence,
          cursor: 'opaque-cursor',
        ),
      ).thenAnswer((_) async => page);

      final result = await repository.getMediaLibraryPage(
        sessionFence: _fence,
        cursor: 'opaque-cursor',
      );

      expect(result.getRight().toNullable(), same(page));
      verify(
        () => remote.getMediaLibraryPage(
          sessionFence: _fence,
          cursor: 'opaque-cursor',
        ),
      ).called(1);
    });
  });
}
