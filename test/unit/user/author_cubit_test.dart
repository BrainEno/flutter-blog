import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockGetAuthorProfile extends Mock implements GetAuthorProfile {}

class MockFollowAuthor extends Mock implements FollowAuthor {}

class MockUnfollowAuthor extends Mock implements UnfollowAuthor {}

AuthorProfile _profile({bool isFollowing = false, int followers = 12}) =>
    AuthorProfile(
      userId: 'author-1',
      displayName: '作者甲',
      followerCount: followers,
      isFollowing: isFollowing,
      updatedAt: DateTime.utc(2025),
    );

void main() {
  late MockGetAuthorProfile getAuthorProfile;
  late MockFollowAuthor followAuthor;
  late MockUnfollowAuthor unfollowAuthor;
  late AuthorCubit cubit;

  setUp(() {
    getAuthorProfile = MockGetAuthorProfile();
    followAuthor = MockFollowAuthor();
    unfollowAuthor = MockUnfollowAuthor();
    // The constructor starts loading immediately, so a default answer must
    // exist before the cubit is built; individual tests override it before
    // their own load() call.
    when(() => getAuthorProfile('author-1')).thenAnswer(
      (_) async => right<Failure, AuthorProfile>(_profile()),
    );
    cubit = AuthorCubit(
      getAuthorProfile: getAuthorProfile,
      followAuthor: followAuthor,
      unfollowAuthor: unfollowAuthor,
      userId: 'author-1',
    );
  });

  tearDown(() => cubit.close());

  group('load', () {
    test('resolves the profile with the viewer follow state', () async {
      when(() => getAuthorProfile('author-1')).thenAnswer(
        (_) async => right<Failure, AuthorProfile>(_profile(isFollowing: true)),
      );

      await cubit.load();

      final state = cubit.state;
      expect(state, isA<AuthorLoaded>());
      expect((state as AuthorLoaded).profile.isFollowing, isTrue);
    });

    test('a failure lands in the failure state with the message', () async {
      when(
        () => getAuthorProfile('author-1'),
      ).thenAnswer((_) async => left<Failure, AuthorProfile>(Failure('作者不存在')));

      await cubit.load();

      expect(cubit.state, isA<AuthorFailure>());
      expect((cubit.state as AuthorFailure).error, '作者不存在');
    });
  });

  group('toggleFollow', () {
    test('following replaces the profile with the server answer', () async {
      when(() => getAuthorProfile('author-1')).thenAnswer(
        (_) async =>
            right<Failure, AuthorProfile>(_profile(isFollowing: false)),
      );
      await cubit.load();

      when(() => followAuthor('author-1')).thenAnswer(
        (_) async => right<Failure, AuthorProfile>(
          _profile(isFollowing: true, followers: 13),
        ),
      );

      await cubit.toggleFollow();

      final state = cubit.state as AuthorLoaded;
      expect(state.profile.isFollowing, isTrue);
      expect(state.profile.followerCount, 13);
      expect(state.followInFlight, isFalse);
      expect(state.followError, isEmpty);
    });

    test(
      'unfollowing calls the unfollow usecase and takes its answer',
      () async {
        when(() => getAuthorProfile('author-1')).thenAnswer(
          (_) async =>
              right<Failure, AuthorProfile>(_profile(isFollowing: true)),
        );
        await cubit.load();

        when(() => unfollowAuthor('author-1')).thenAnswer(
          (_) async => right<Failure, AuthorProfile>(
            _profile(isFollowing: false, followers: 11),
          ),
        );

        await cubit.toggleFollow();

        final state = cubit.state as AuthorLoaded;
        expect(state.profile.isFollowing, isFalse);
        expect(state.profile.followerCount, 11);
        verify(() => unfollowAuthor('author-1')).called(1);
        verifyNever(() => followAuthor(any()));
      },
    );

    test(
      'a failed toggle keeps the previous server state and reports it',
      () async {
        when(() => getAuthorProfile('author-1')).thenAnswer(
          (_) async =>
              right<Failure, AuthorProfile>(_profile(isFollowing: true)),
        );
        await cubit.load();

        when(() => unfollowAuthor('author-1')).thenAnswer(
          (_) async => left<Failure, AuthorProfile>(Failure('网络超时')),
        );

        await cubit.toggleFollow();

        final state = cubit.state as AuthorLoaded;
        // The server-resolved state is untouched on failure.
        expect(state.profile.isFollowing, isTrue);
        expect(state.followInFlight, isFalse);
        expect(state.followError, '网络超时');
      },
    );

    test('a rapid second tap is ignored while a toggle is in flight', () async {
      when(() => getAuthorProfile('author-1')).thenAnswer(
        (_) async =>
            right<Failure, AuthorProfile>(_profile(isFollowing: false)),
      );
      await cubit.load();

      var completions = 0;
      when(() => followAuthor('author-1')).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        completions++;
        return right<Failure, AuthorProfile>(_profile(isFollowing: true));
      });

      // Two taps before the first request completes: the in-flight guard
      // must drop the second one.
      final first = cubit.toggleFollow();
      final second = cubit.toggleFollow();
      await first;
      await second;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(completions, 1);
      verify(() => followAuthor('author-1')).called(1);
    });

    test('a toggle before the profile loads is ignored', () async {
      // The constructor already started a load; hold it back so the state
      // is still AuthorLoading when the toggle arrives.
      final loadCompleter = Completer<Either<Failure, AuthorProfile>>();
      when(
        () => getAuthorProfile('author-1'),
      ).thenAnswer((_) => loadCompleter.future);

      final lateCubit = AuthorCubit(
        getAuthorProfile: getAuthorProfile,
        followAuthor: followAuthor,
        unfollowAuthor: unfollowAuthor,
        userId: 'author-1',
      );
      addTearDown(lateCubit.close);

      await lateCubit.toggleFollow();

      expect(lateCubit.state, isA<AuthorLoading>());
      verifyNever(() => followAuthor(any()));
      verifyNever(() => unfollowAuthor(any()));
    });
  });
}
