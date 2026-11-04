import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockToggleLike extends Mock implements ToggleLikeBlog {}

class _MockIsLiked extends Mock implements IsBlogLiked {}

class _MockGetLiked extends Mock implements GetUserLikedBlogs {}

class _ToggleParamsFake extends Fake implements ToggleLikeParams {}

class _IsLikedParamsFake extends Fake implements IsBlogLikedParams {}

class _LikedParamsFake extends Fake implements GetUserLikedBlogsParams {}

/// The signed-in account, switchable mid-test.
class _FakeSession implements NowaveSessionIdentity {
  _FakeSession(this._userId);

  String? _userId;

  int _generation = 1;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  String? get activeUserId => _userId;

  @override
  String? get accessToken => _userId == null ? null : 'token-$_userId';

  @override
  int get sessionGeneration => _generation;

  @override
  Stream<void> get identityChanges => _changes.stream;

  void switchTo(String? next) {
    _userId = next;
    _generation += 1;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

Blog _blog(String title) => Blog(
  id: title,
  title: title,
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

void main() {
  late _MockToggleLike toggleLike;
  late _MockIsLiked isLiked;
  late _MockGetLiked getLiked;
  late _FakeSession session;
  late BlogLikedBloc bloc;

  setUpAll(() {
    registerFallbackValue(_ToggleParamsFake());
    registerFallbackValue(_IsLikedParamsFake());
    registerFallbackValue(_LikedParamsFake());
  });

  setUp(() {
    toggleLike = _MockToggleLike();
    isLiked = _MockIsLiked();
    getLiked = _MockGetLiked();
    session = _FakeSession('A');
    bloc = BlogLikedBloc(
      toggleBlogLike: toggleLike,
      isBlogLiked: isLiked,
      getUserLikedBlogs: getLiked,
      sessionIdentity: session,
    );
    addTearDown(bloc.close);
    addTearDown(session.dispose);
  });

  /// `/me/liked-articles` answers for whoever is signed in.
  void serveLikedByViewer() {
    when(() => getLiked(any())).thenAnswer(
      (_) async => right(<Blog>[_blog('${session.activeUserId} 收藏')]),
    );
  }

  test('the saved list reloads for the new account on a switch', () async {
    serveLikedByViewer();
    final loaded = bloc.stream.firstWhere(
      (state) => state is UserLikedBlogsSuccess,
    );
    bloc.add(UserLikedBlogs(userId: 'A'));
    expect(
      ((await loaded) as UserLikedBlogsSuccess).blogs.single.title,
      'A 收藏',
    );

    final reloaded = bloc.stream.firstWhere(
      (state) =>
          state is UserLikedBlogsSuccess && state.blogs.single.title == 'B 收藏',
    );
    session.switchTo('B');
    await reloaded;

    expect(bloc.state, isA<UserLikedBlogsSuccess>());
    expect(
      (bloc.state as UserLikedBlogsSuccess).blogs.single.title,
      'B 收藏',
      reason: 'A 的收藏不能留在 B 的界面上',
    );
    verify(() => getLiked(any())).called(2);
  });

  test('the like icon is re-read for the new account', () async {
    when(
      () => isLiked(any()),
    ).thenAnswer((_) async => right(session.activeUserId == 'A'));
    final read = bloc.stream.firstWhere(
      (state) => state is GetBlogIsLikedSuccess,
    );
    bloc.add(GetIsBlogLiked(userId: 'A', blogId: 'x'));
    expect(((await read) as GetBlogIsLikedSuccess).isLiked, isTrue);

    final reread = bloc.stream.firstWhere(
      (state) => state is GetBlogIsLikedSuccess && !state.isLiked,
    );
    session.switchTo('B');
    await reread;

    expect((bloc.state as GetBlogIsLikedSuccess).blogId, 'x');
    final params = verify(
      () => isLiked(captureAny()),
    ).captured.cast<IsBlogLikedParams>();
    expect(params.last.userId, 'B');
  });

  test('a tap made by the old account is dropped after a switch', () async {
    final pending = Completer<Either<Failure, bool>>();
    when(() => toggleLike(any())).thenAnswer((_) => pending.future);

    final states = <BlogLikedState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    bloc.add(ToggleBlogLike(userId: 'A', blogId: 'x'));
    await Future<void>.delayed(Duration.zero);
    session.switchTo('B');
    // A's response arrives after the switch: it must not render as B's like.
    pending.complete(right(true));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state, isA<BlogLikedInitial>(), reason: 'A 的点赞结果不能写成 B 的状态');
    expect(states.whereType<ToggleBlogLikeFailure>(), isEmpty);
  });

  test('signing out clears the liked map and stops requesting', () async {
    when(() => isLiked(any())).thenAnswer((_) async => right(true));
    final read = bloc.stream.firstWhere(
      (state) => state is GetBlogIsLikedSuccess,
    );
    bloc.add(GetIsBlogLiked(userId: 'A', blogId: 'x'));
    await read;
    clearInteractions(isLiked);

    final cleared = bloc.stream.firstWhere(
      (state) => state is BlogLikedInitial,
    );
    session.switchTo(null);
    await cleared;

    expect(bloc.state, isA<BlogLikedInitial>());
    verifyNever(() => isLiked(any()));
  });
}
