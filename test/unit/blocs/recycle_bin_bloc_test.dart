import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockGetDeletedBlogs extends Mock implements GetDeletedBlogs {}

class MockRestoreDeletedBlog extends Mock implements RestoreDeletedBlog {}

class _NoParamsFake extends Fake implements NoParams {}

DeletedBlog _tombstone(String articleId, {String title = '被删的文章'}) =>
    DeletedBlog(
      articleId: articleId,
      title: title,
      imageUrl: '',
      deletedAt: DateTime.utc(2026, 10, 1),
      purgesAt: DateTime.utc(2026, 10, 31),
    );

Blog _restoredBlog() => Blog(
      id: 'my-slug',
      title: '被删的文章',
      content: '正文',
      posterId: 'u1',
      imageUrl: '',
      tags: const [],
      updatedAt: DateTime.utc(2026),
    );

void main() {
  late MockGetDeletedBlogs getDeletedBlogs;
  late MockRestoreDeletedBlog restoreDeletedBlog;
  late RecycleBinBloc bloc;

  setUpAll(() {
    registerFallbackValue(_NoParamsFake());
    registerFallbackValue(RestoreDeletedBlogParams(articleId: 'fallback'));
  });

  setUp(() {
    getDeletedBlogs = MockGetDeletedBlogs();
    restoreDeletedBlog = MockRestoreDeletedBlog();
    bloc = RecycleBinBloc(
      getDeletedBlogs: getDeletedBlogs,
      restoreDeletedBlog: restoreDeletedBlog,
    );
    addTearDown(bloc.close);
  });

  /// Loads the bin with [blogs] and returns the resulting success state.
  Future<RecycleBinSuccess> load(List<DeletedBlog> blogs) async {
    when(
      () => getDeletedBlogs(any()),
    ).thenAnswer((_) async => right(blogs));
    final states = <RecycleBinState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(RecycleBinRequested());
    await bloc.stream.firstWhere((state) => state is RecycleBinSuccess);
    await sub.cancel();
    return states.whereType<RecycleBinSuccess>().single;
  }

  test('requesting the bin loads the tombstones', () async {
    final success = await load([_tombstone('a1'), _tombstone('a2')]);

    expect(success.blogs.map((blog) => blog.articleId), ['a1', 'a2']);
    expect(success.lastRestoredTitle, isNull);
    expect(success.restoringArticleId, isNull);
  });

  test('a failed load reports the failure', () async {
    when(
      () => getDeletedBlogs(any()),
    ).thenAnswer((_) async => left(Failure('加载失败')));

    bloc.add(RecycleBinRequested());
    final state = await bloc.stream
        .firstWhere((state) => state is RecycleBinFailure);

    expect((state as RecycleBinFailure).error, '加载失败');
  });

  test('a restore removes the tombstone and reports the title', () async {
    await load([_tombstone('a1'), _tombstone('a2')]);

    when(
      () => restoreDeletedBlog(any()),
    ).thenAnswer((_) async => right(_restoredBlog()));

    bloc.add(RecycleBinRestoreRequested(articleId: 'a1'));
    final state = await bloc.stream.firstWhere(
      (state) => state is RecycleBinSuccess && state.blogs.length == 1,
    );

    final success = state as RecycleBinSuccess;
    expect(success.blogs.single.articleId, 'a2');
    expect(success.lastRestoredTitle, '被删的文章');
    expect(success.restoringArticleId, isNull);
  });

  test('a failed restore keeps the list and surfaces the message', () async {
    await load([_tombstone('a1')]);

    when(
      () => restoreDeletedBlog(any()),
    ).thenAnswer((_) async => left(Failure('没有权限执行此操作')));

    bloc.add(RecycleBinRestoreRequested(articleId: 'a1'));
    final state = await bloc.stream
        .firstWhere((state) => state is RecycleBinRestoreFailure);

    final failure = state as RecycleBinRestoreFailure;
    expect(failure.message, '没有权限执行此操作');
    expect(failure.blogs.map((blog) => blog.articleId), ['a1']);
  });

  test('a second restore while one is in flight is ignored', () async {
    await load([_tombstone('a1'), _tombstone('a2')]);

    var restoreCalls = 0;
    when(() => restoreDeletedBlog(any())).thenAnswer((_) async {
      restoreCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return right(_restoredBlog());
    });

    bloc.add(RecycleBinRestoreRequested(articleId: 'a1'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    bloc.add(RecycleBinRestoreRequested(articleId: 'a2'));
    await bloc.stream.firstWhere(
      (state) => state is RecycleBinSuccess && state.blogs.length == 1,
    );
    // Give an (incorrectly admitted) second restore time to land.
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(restoreCalls, 1);
  });
}
