import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetDeletedBlogs extends Mock implements GetDeletedBlogs {}

class _MockRestoreDeletedBlog extends Mock implements RestoreDeletedBlog {}

class _NoParamsFake extends Fake implements NoParams {}

/// A session whose account can be switched mid-test, exactly as the real
/// manager does: the id changes and the generation moves on.
class _FakeSession implements NowaveSessionIdentity {
  _FakeSession(this._userId);

  String? _userId;

  int _generation = 1;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  String? get activeUserId => _userId;

  @override
  String? get accessToken =>
      _userId == null ? null : 'token-$_userId';

  @override
  int get sessionGeneration => _generation;

  @override
  Stream<void> get identityChanges => _changes.stream;

  /// Switches to [next] (null signs out) and notifies listeners.
  void switchTo(String? next) {
    _userId = next;
    _generation += 1;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

DeletedBlog _tombstone(String owner) => DeletedBlog(
  articleId: '$owner-article',
  title: '$owner 的被删文章',
  imageUrl: '',
  deletedAt: DateTime.utc(2026, 10, 1),
  purgesAt: DateTime.utc(2026, 10, 31),
);

Blog _restored(String owner) => Blog(
  id: '$owner-restored',
  title: '$owner 恢复的文章',
  content: '正文',
  posterId: owner,
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

void main() {
  late _MockGetDeletedBlogs getDeletedBlogs;
  late _MockRestoreDeletedBlog restoreDeletedBlog;
  late _FakeSession session;
  late RecycleBinBloc bloc;

  setUpAll(() {
    registerFallbackValue(_NoParamsFake());
    registerFallbackValue(RestoreDeletedBlogParams(articleId: 'fallback'));
  });

  /// Serves whoever is signed in, like `/me/articles/deleted` does.
  void serveBinByOwner() {
    when(() => getDeletedBlogs(any())).thenAnswer((_) async {
      final owner = session.activeUserId;
      if (owner == null) return left(const Failure('用户未登录'));
      return right(<DeletedBlog>[_tombstone(owner)]);
    });
  }

  setUp(() {
    getDeletedBlogs = _MockGetDeletedBlogs();
    restoreDeletedBlog = _MockRestoreDeletedBlog();
    session = _FakeSession('A');
    bloc = RecycleBinBloc(
      getDeletedBlogs: getDeletedBlogs,
      restoreDeletedBlog: restoreDeletedBlog,
      sessionIdentity: session,
    );
    addTearDown(bloc.close);
    addTearDown(session.dispose);
  });

  Future<RecycleBinState> stateWhere(bool Function(RecycleBinState) test) =>
      bloc.stream.firstWhere(test);

  test('a switch drops the previous account tombstones and reloads', () async {
    serveBinByOwner();
    final loaded = stateWhere((state) => state is RecycleBinSuccess);
    bloc.add(RecycleBinRequested());
    final first = await loaded;
    expect((first as RecycleBinSuccess).blogs.single.title, 'A 的被删文章');

    final next = stateWhere(
      (state) =>
          state is RecycleBinSuccess && state.blogs.single.title == 'B 的被删文章',
    );
    session.switchTo('B');
    final second = await next;

    expect((second as RecycleBinSuccess).blogs.single.articleId, 'B-article');
    expect(bloc.state, isA<RecycleBinSuccess>(), reason: 'A 的列表不能停留在界面上');
  });

  test('a read across the switch never shows the old account', () async {
    final pending = Completer<Either<Failure, List<DeletedBlog>>>();
    var calls = 0;
    when(() => getDeletedBlogs(any())).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) return pending.future;
      return right(<DeletedBlog>[_tombstone('B')]);
    });

    final states = <RecycleBinState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    final reloaded = stateWhere(
      (state) =>
          state is RecycleBinSuccess && state.blogs.single.title == 'B 的被删文章',
    );
    bloc.add(RecycleBinRequested());
    await Future<void>.delayed(Duration.zero);
    session.switchTo('B');
    // A's response lands after the switch: it must be dropped.
    pending.complete(right(<DeletedBlog>[_tombstone('A')]));
    await reloaded;

    expect(
      states.whereType<RecycleBinSuccess>().map((s) => s.blogs.single.title),
      isNot(contains('A 的被删文章')),
    );
  });

  test('a restore across the switch does not resurrect the bin', () async {
    serveBinByOwner();
    final loaded = stateWhere((state) => state is RecycleBinSuccess);
    bloc.add(RecycleBinRequested());
    await loaded;

    final pending = Completer<Either<Failure, Blog>>();
    when(() => restoreDeletedBlog(any())).thenAnswer((_) => pending.future);

    final states = <RecycleBinState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    final restoring = stateWhere(
      (state) => state is RecycleBinSuccess && state.restoringArticleId != null,
    );
    bloc.add(RecycleBinRestoreRequested(articleId: 'A-article'));
    await restoring;

    final reloaded = stateWhere(
      (state) =>
          state is RecycleBinSuccess &&
          state.blogs.single.articleId == 'B-article',
    );
    final beforeSwitch = states.length;
    session.switchTo('B');
    pending.complete(right(_restored('A')));
    await reloaded;

    expect(
      states
          .skip(beforeSwitch)
          .whereType<RecycleBinSuccess>()
          .map((state) => state.blogs.single.articleId),
      isNot(contains('A-article')),
      reason: '恢复的响应属于上一个账号，不能带回它的列表',
    );
  });

  test('signing out clears the bin without asking the server', () async {
    serveBinByOwner();
    final loaded = stateWhere((state) => state is RecycleBinSuccess);
    bloc.add(RecycleBinRequested());
    await loaded;
    clearInteractions(getDeletedBlogs);

    final cleared = stateWhere((state) => state is RecycleBinInitial);
    session.switchTo(null);
    await cleared;

    expect(bloc.state, isA<RecycleBinInitial>());
    verifyNever(() => getDeletedBlogs(any()));
  });

  test('with no session injected nothing subscribes', () async {
    final plain = RecycleBinBloc(
      getDeletedBlogs: getDeletedBlogs,
      restoreDeletedBlog: restoreDeletedBlog,
    );
    addTearDown(plain.close);
    when(
      () => getDeletedBlogs(any()),
    ).thenAnswer((_) async => right(<DeletedBlog>[_tombstone('A')]));

    final loaded = plain.stream.firstWhere(
      (state) => state is RecycleBinSuccess,
    );
    plain.add(RecycleBinRequested());
    await loaded;

    session.switchTo('B');
    await Future<void>.delayed(Duration.zero);
    expect((plain.state as RecycleBinSuccess).blogs.single.title, 'A 的被删文章');
  });
}
