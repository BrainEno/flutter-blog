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

Blog _blog(String id) => Blog(
  id: id,
  title: id,
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

/// The bug: the saved tab is built once and kept alive behind the other
/// tabs, with its own bloc. Saving an article in the home tab never reached
/// it, so it kept saying "you have not saved anything".
void main() {
  late _MockToggleLike toggleLike;
  late _MockIsLiked isLiked;
  late _MockGetLiked getLiked;
  late SavedArticlesChanges changes;

  /// What `/me/liked-articles` answers right now.
  var saved = <Blog>[];

  setUpAll(() {
    registerFallbackValue(_ToggleParamsFake());
    registerFallbackValue(_IsLikedParamsFake());
    registerFallbackValue(_LikedParamsFake());
  });

  setUp(() {
    toggleLike = _MockToggleLike();
    isLiked = _MockIsLiked();
    getLiked = _MockGetLiked();
    changes = SavedArticlesChanges();
    addTearDown(changes.dispose);
    saved = <Blog>[];
    when(() => getLiked(any())).thenAnswer((_) async => right(saved));
    when(() => isLiked(any())).thenAnswer((_) async => right(false));
    when(() => toggleLike(any())).thenAnswer((_) async {
      saved = [_blog('a')];
      return right(true);
    });
  });

  BlogLikedBloc page() {
    final bloc = BlogLikedBloc(
      toggleBlogLike: toggleLike,
      isBlogLiked: isLiked,
      getUserLikedBlogs: getLiked,
      savedChanges: changes,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  test('a save in another tab reloads a saved list that is already '
      'built', () async {
    final savedTab = page();
    savedTab.add(UserLikedBlogs(userId: 'reader'));
    await savedTab.stream.firstWhere((s) => s is UserLikedBlogsSuccess);
    expect((savedTab.state as UserLikedBlogsSuccess).blogs, isEmpty);

    final viewer = page();
    final reloaded = savedTab.stream.firstWhere(
      (s) => s is UserLikedBlogsSuccess && s.blogs.isNotEmpty,
    );
    viewer.add(ToggleBlogLike(userId: 'reader', blogId: 'a'));

    final state = (await reloaded) as UserLikedBlogsSuccess;
    expect(state.blogs.single.id, 'a');
    expect(state.likedBlogs['a'], isTrue);
  });

  test('the same article open in another tab follows the new state', () async {
    final elsewhere = page();
    elsewhere.add(GetIsBlogLiked(userId: 'reader', blogId: 'a'));
    await elsewhere.stream.firstWhere((s) => s is GetBlogIsLikedSuccess);
    expect(elsewhere.state.likedBlogs['a'], isFalse);

    final viewer = page();
    final followed = elsewhere.stream.firstWhere(
      (s) => s.likedBlogs['a'] == true,
    );
    viewer.add(ToggleBlogLike(userId: 'reader', blogId: 'a'));
    await followed;

    // It follows without asking the server again or reloading a list it
    // never showed.
    verify(() => isLiked(any())).called(1);
    expect(elsewhere.state, isA<GetBlogIsLikedSuccess>());
  });

  test('a page does not react to its own save, nor to another '
      "account's", () async {
    final viewer = page();
    viewer.add(GetIsBlogLiked(userId: 'reader', blogId: 'a'));
    await viewer.stream.firstWhere((s) => s is GetBlogIsLikedSuccess);

    viewer.add(ToggleBlogLike(userId: 'reader', blogId: 'a'));
    await viewer.stream.firstWhere((s) => s is UserLikedBlogsSuccess);
    await Future<void>.delayed(Duration.zero);
    // One list read: the refresh after its own toggle, no echo.
    verify(() => getLiked(any())).called(1);

    final other = page();
    other.add(UserLikedBlogs(userId: 'someone-else'));
    await other.stream.firstWhere((s) => s is UserLikedBlogsSuccess);
    clearInteractions(getLiked);
    changes.publish(
      SavedArticleChange(
        userId: 'reader',
        blogId: 'b',
        saved: true,
        source: Object(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    verifyNever(() => getLiked(any()));
  });
}
