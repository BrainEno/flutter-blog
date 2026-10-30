import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/models/author_profile_model.dart';
import 'package:belog/features/user/data/repositories/author_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthorRemote extends Mock implements AuthorRemoteDataSource {}

class MockConnection extends Mock implements ConnectionChecker {}

AuthorProfileModel _profile({bool isFollowing = false}) => AuthorProfileModel(
  userId: 'author-1',
  displayName: '作者甲',
  followerCount: 12,
  isFollowing: isFollowing,
  updatedAt: DateTime.utc(2025),
);

void main() {
  late MockAuthorRemote remote;
  late MockConnection connection;
  late AuthorRepositoryImpl repository;

  setUp(() {
    remote = MockAuthorRemote();
    connection = MockConnection();
    repository = AuthorRepositoryImpl(
      authorRemoteDataSource: remote,
      connectionChecker: connection,
    );
    when(() => connection.isConnected).thenAnswer((_) async => true);
  });

  group('getAuthorProfile', () {
    test('returns the profile on success', () async {
      when(
        () => remote.getAuthorProfile('author-1'),
      ).thenAnswer((_) async => _profile(isFollowing: true));

      final result = await repository.getAuthorProfile('author-1');

      result.fold(
        (failure) => fail('expected success'),
        (profile) => expect(profile.isFollowing, isTrue),
      );
    });

    test(
      'offline returns a network failure without calling the server',
      () async {
        when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.getAuthorProfile('author-1');

      result.fold(
        (failure) => expect(failure.code, 'network.offline'),
        (_) => fail('offline load must not succeed'),
      );
        verifyNever(() => remote.getAuthorProfile(any()));
      },
    );

    test('a missing author is returned as a validation failure', () async {
      // The mapper classifies NOT_FOUND as validation (a page-level
      // "not found" the UI renders instead of a snackbar-worthy error).
      when(() => remote.getAuthorProfile('author-1')).thenThrow(
        const ServerException(
          'The requested resource was not found.',
          kind: FailureKind.validation,
        ),
      );

      final result = await repository.getAuthorProfile('author-1');

      result.fold(
        (failure) => expect(failure.kind, FailureKind.validation),
        (_) => fail('expected failure'),
      );
    });
  });

  group('followAuthor', () {
    test('returns the fresh profile from the server', () async {
      when(
        () => remote.followAuthor('author-1'),
      ).thenAnswer((_) async => _profile(isFollowing: true));

      final result = await repository.followAuthor('author-1');

      result.fold(
        (failure) => fail('expected success'),
        (profile) {
          expect(profile.isFollowing, isTrue);
          expect(profile.followerCount, 12);
        },
      );
    });

    test('offline keeps a follow-specific message', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.followAuthor('author-1');

      result.fold(
        (failure) => expect(failure.message, contains('关注未同步')),
        (_) => fail('offline follow must not succeed'),
      );
      verifyNever(() => remote.followAuthor(any()));
    });
  });

  group('unfollowAuthor', () {
    test('offline keeps an unfollow-specific message', () async {
      when(() => connection.isConnected).thenAnswer((_) async => false);

      final result = await repository.unfollowAuthor('author-1');

      result.fold(
        (failure) => expect(failure.message, contains('取消关注未同步')),
        (_) => fail('offline unfollow must not succeed'),
      );
      verifyNever(() => remote.unfollowAuthor(any()));
    });
  });
}
