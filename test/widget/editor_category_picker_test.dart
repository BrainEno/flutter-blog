import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/editor_category_selector.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

/// Records the events the editor dispatches instead of publishing anything.
class _RecordingUploadBloc extends Mock implements BlogUploadBloc {
  final List<BlogUploadEvent> events = [];

  @override
  void add(BlogUploadEvent event) => events.add(event);
}

class _FakeDraftStore implements BlogDraftStore {
  BlogDraft? saved;

  @override
  Future<BlogDraft?> load(String? blogId, {required String userId}) async =>
      null;

  @override
  Future<void> save(BlogDraft draft) async => saved = draft;

  @override
  Future<bool> discardIfUnchanged(BlogDraft draft) async => true;

  @override
  Future<bool> hasUnclaimedDrafts() async => false;

  @override
  Future<int> deleteDraftsFor(
    String? blogId, {
    required String userId,
    DateTime? olderThan,
  }) async => 0;
}

class _FakeCategoryRepository implements CategoryRepository {
  _FakeCategoryRepository(this.categories, {this.failure});

  final List<CategoryRef> categories;
  final Failure? failure;

  @override
  Future<Either<Failure, List<CategoryRef>>> listCategories() async {
    final failure = this.failure;
    return failure == null ? right(categories) : left(failure);
  }

  @override
  Future<Either<Failure, CategoryRef?>> getCategory(String slug) async =>
      right(null);

  @override
  Future<Either<Failure, List<Blog>>> getArticlesByCategory(
    String slug, {
    required int offset,
  }) async => right(const []);
}

class _FakeSession implements NowaveSessionIdentity {
  _FakeSession(this.userId);

  String? userId;
  int generation = 1;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;
  @override
  String? get accessToken => userId == null ? null : 'synthetic-token';
  @override
  int get sessionGeneration => generation;
  @override
  Stream<void> get identityChanges => _changes.stream;

  void dispose() => _changes.close();
}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: 'Synthetic user',
  updatedAt: DateTime.utc(2024),
);

Blog _blog(List<String> categoryIds) => Blog(
  id: 'a-slug',
  title: '已发布标题',
  content: '已发布正文',
  posterId: 'author',
  imageUrl: '',
  tags: const ['诗歌'],
  updatedAt: DateTime.utc(2025),
  categoryIds: categoryIds,
);

const _categories = [
  CategoryRef(id: 'cat-1', slug: 'essay', name: '随笔'),
  CategoryRef(id: 'cat-2', slug: 'poem', name: '诗'),
];

Future<_RecordingUploadBloc> _openEditor(
  WidgetTester tester, {
  required Blog blog,
  required GetCategories source,
  required _FakeDraftStore store,
}) async {
  final bloc = _RecordingUploadBloc();
  when(() => bloc.state).thenReturn(BlogUploadInitial());
  when(
    () => bloc.stream,
  ).thenAnswer((_) => const Stream<BlogUploadState>.empty());
  final user = AppUserCubit()..updateUser(_user('user'));
  final session = _FakeSession('user');
  addTearDown(user.close);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<BlogUploadBloc>.value(value: bloc),
          BlocProvider<AppUserCubit>.value(value: user),
        ],
        child: BlogEditorPage(
          blog: blog,
          draftStore: store,
          sessionIdentity: session,
          getCategories: source,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

Future<void> _publish(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the picker offers the server catalog and publishes the picks', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const []),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    expect(find.text('随笔'), findsOneWidget);
    expect(find.text('诗'), findsOneWidget);

    await tester.tap(find.text('诗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();
    await _publish(tester, '发布');

    final event = bloc.events.single;
    expect(event, isA<UpdateBlogEvent>());
    // Multi-select: the second tap adds, it does not replace the first. The
    // order is the order the author picked; the server sorts.
    expect((event as UpdateBlogEvent).categoryIds, ['cat-2', 'cat-1']);
  });

  testWidgets('an article in two categories keeps the one not tapped', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const ['cat-1', 'cat-2']),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    // The author removes one of the two; the other is still theirs.
    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();
    await _publish(tester, '发布');

    expect((bloc.events.single as UpdateBlogEvent).categoryIds, ['cat-2']);
  });

  testWidgets('a category the catalog cannot name survives the edit', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const ['cat-1', 'cat-3']),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    // The catalog is one page in one language, so `cat-3` has no chip. It is
    // still the article's, and the row says so rather than silently editing it
    // away.
    expect(find.text('另有 1 个分类不在当前目录里，保持原样。'), findsOneWidget);

    await tester.tap(find.text('诗'));
    await tester.pumpAndSettle();
    await _publish(tester, '发布');

    expect((bloc.events.single as UpdateBlogEvent).categoryIds, [
      'cat-1',
      'cat-3',
      'cat-2',
    ]);
  });

  testWidgets('an untouched picker sends nothing, so nothing is cleared', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const ['cat-1']),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    // The article's own category shows as selected without being "chosen".
    final chip = tester.widget<InputChip>(
      find.ancestor(of: find.text('随笔'), matching: find.byType(InputChip)),
    );
    expect(chip.selected, isTrue);

    await _publish(tester, '发布');

    final event = bloc.events.single as UpdateBlogEvent;
    // Null, not an empty list: the write omits `categoryIds` entirely and the
    // article keeps the category it has.
    expect(event.categoryIds, isNull);
  });

  testWidgets('clearing the selection is a choice, not an omission', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const ['cat-1']),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();
    await _publish(tester, '发布');

    final event = bloc.events.single as UpdateBlogEvent;
    expect(event.categoryIds, isEmpty);
  });

  testWidgets('a missing catalog never blocks the editor', (tester) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const []),
      source: GetCategories(
        _FakeCategoryRepository(
          _categories,
          failure: const Failure('offline', kind: FailureKind.network),
        ),
      ),
      store: store,
    );

    expect(find.text('分类没有读到，可以重试；不选也照常发布。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await _publish(tester, '发布');
    final event = bloc.events.single as UpdateBlogEvent;
    expect(event.categoryIds, isNull);
  });

  testWidgets('clearing every chip is still a choice, not an omission', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const ['cat-1', 'cat-2']),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诗'));
    await tester.pumpAndSettle();
    await _publish(tester, '发布');

    // Empty, not null: the author looked and chose none.
    expect((bloc.events.single as UpdateBlogEvent).categoryIds, isEmpty);
  });

  testWidgets('the draft keeps every pick, not just the last one', (
    tester,
  ) async {
    final store = _FakeDraftStore();
    final bloc = await _openEditor(
      tester,
      blog: _blog(const []),
      source: GetCategories(_FakeCategoryRepository(_categories)),
      store: store,
    );

    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诗'));
    await tester.pumpAndSettle();
    await _publish(tester, '发布');

    expect((bloc.events.single as UpdateBlogEvent).categoryIds, [
      'cat-1',
      'cat-2',
    ]);
    expect(store.saved?.categoryIds, ['cat-1', 'cat-2']);
  });

  testWidgets('the chips stop at the server limit', (tester) async {
    var latest = const <String>[];
    await _pumpSelector(
      tester,
      categories: const [
        CategoryRef(id: 'cat-1', slug: 'a', name: '一'),
        CategoryRef(id: 'cat-2', slug: 'b', name: '二'),
        CategoryRef(id: 'cat-3', slug: 'c', name: '三'),
        CategoryRef(id: 'cat-4', slug: 'd', name: '四'),
      ],
      selected: const [],
      maxSelections: 3,
      onChanged: (ids) => latest = ids,
    );

    for (final label in ['一', '二', '三']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(latest, ['cat-1', 'cat-2', 'cat-3']);
    expect(find.text('最多 3 个分类，要换一个得先取消一个。'), findsOneWidget);

    // The fourth chip does nothing rather than silently dropping one of the
    // three the author already has.
    await tester.tap(find.text('四'));
    await tester.pumpAndSettle();
    expect(latest, ['cat-1', 'cat-2', 'cat-3']);
  });
}

/// Pumps the row on its own, for bounds that would take too many taps to
/// reach through the whole editor.
Future<void> _pumpSelector(
  WidgetTester tester, {
  required List<CategoryRef> categories,
  required List<String> selected,
  required int maxSelections,
  required ValueChanged<List<String>> onChanged,
}) async {
  var current = selected;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => EditorCategorySelector(
            categories: categories,
            selectedIds: current,
            isLoading: false,
            hasFailed: false,
            maxSelections: maxSelections,
            onChanged: (ids) {
              onChanged(ids);
              setState(() => current = ids);
            },
            onRetry: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
