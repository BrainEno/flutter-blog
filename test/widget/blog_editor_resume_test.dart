import 'dart:async';
import 'dart:convert';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/editor_body_field.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import '../support/publish_queue_fakes.dart';

/// A 1x1 transparent PNG, so the cover preview decodes instead of failing.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUA'
  'Aen63NgAAAAASUVORK5CYII=',
);

class _Identity implements NowaveSessionIdentity {
  String? userId = 'user';
  final controller = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;

  @override
  String? get accessToken => userId == null ? null : 'synthetic-token';

  @override
  int get sessionGeneration => 1;

  @override
  Stream<void> get identityChanges => controller.stream;
}

class _FakeDraftStore implements BlogDraftStore {
  BlogDraft? draft;
  final List<BlogDraft> saved = [];

  @override
  Future<BlogDraft?> load(String? blogId, {required String userId}) async =>
      draft;

  @override
  Future<void> save(BlogDraft draft) async {
    saved.add(draft);
    this.draft = draft;
  }

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

class _Catalog implements CategoryRepository {
  _Catalog(this.categories);

  final List<CategoryRef> categories;

  @override
  Future<Either<Failure, List<CategoryRef>>> listCategories() async =>
      right(categories);

  @override
  Future<Either<Failure, CategoryRef?>> getCategory(String slug) async =>
      right(null);

  @override
  Future<Either<Failure, List<Blog>>> getArticlesByCategory(
    String slug, {
    required int offset,
  }) async => right(const []);
}

class _MockMediaUserRepository extends Mock implements UserRepository {}

class _RecordingUploadBloc extends Mock implements BlogUploadBloc {
  _RecordingUploadBloc(this.states);

  final StreamController<BlogUploadState> states;
  final List<BlogUploadEvent> events = [];

  @override
  BlogUploadState get state => BlogUploadInitial();

  @override
  Stream<BlogUploadState> get stream => states.stream;

  @override
  void add(BlogUploadEvent event) => events.add(event);
}

class _Harness {
  _Harness({
    this.queueEntry,
    this.blog,
    List<PublishQueueEntry> rows = const [],
    ImageUpload? cover,
    this.getCategories,
    this.getUserMediaLibraryPage,
  }) : queue = FakePublishQueueStore(rows: rows, storedCover: cover),
       drafts = _FakeDraftStore() {
    identity = _Identity();
    drainer = FakePublishQueueDrainer();
    states = StreamController<BlogUploadState>.broadcast();
    bloc = _RecordingUploadBloc(states);
    user = AppUserCubit()
      ..updateUser(
        User(
          id: 'user',
          email: 'user@example.invalid',
          name: 'Synthetic user',
          updatedAt: DateTime.utc(2024),
        ),
      );
  }

  final PublishQueueEntry? queueEntry;
  final Blog? blog;
  final GetCategories? getCategories;
  final GetUserMediaLibraryPage? getUserMediaLibraryPage;
  final FakePublishQueueStore queue;
  final _FakeDraftStore drafts;
  late final _Identity identity;
  late final FakePublishQueueDrainer drainer;
  late final StreamController<BlogUploadState> states;
  late final _RecordingUploadBloc bloc;
  late final AppUserCubit user;

  Future<void> pump(WidgetTester tester) async {
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
            queueEntry: queueEntry,
            draftStore: drafts,
            sessionIdentity: identity,
            publishQueueStore: queue,
            publishQueueDrainer: drainer,
            getCategories: getCategories,
            getUserMediaLibraryPage: getUserMediaLibraryPage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await user.close();
    await identity.controller.close();
    await states.close();
  }
}

Blog publishedBlog() => Blog(
  id: 'my-slug',
  title: '已发布标题',
  content: '已发布正文',
  posterId: 'user',
  imageUrl: 'https://cdn.example.invalid/old-cover.webp',
  tags: const ['小说'],
  updatedAt: DateTime.utc(2026, 10, 1),
);

String titleText(WidgetTester tester) => tester
    .widget<TextFormField>(find.byType(TextFormField).first)
    .controller!
    .text;

/// The body is a plain text field, so it is addressed by its own widget rather
/// than by index inside the form.
String bodyText(WidgetTester tester) => tester
    .widget<EditorBodyField>(find.byType(EditorBodyField))
    .controller
    .text;

void main() {
  setUpAll(() {
    registerFallbackValue(
      const NowaveSessionFence(userId: 'user', generation: 1),
    );
  });

  testWidgets('a failed entry resumes its text, tags and cover', (
    tester,
  ) async {
    final entry = queueEntry(coverFileName: 'queue-1.bin');
    final harness = _Harness(
      queueEntry: entry,
      rows: [entry],
      cover: ImageUpload(bytes: _pngBytes, mimeType: 'image/png'),
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    expect(titleText(tester), '待发标题');
    expect(bodyText(tester), '待发正文');
    expect(find.text(l10n.publishQueueResumedNotice), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text(l10n.editorNewTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('publishing the resumed text retires the old entry', (
    tester,
  ) async {
    final entry = queueEntry();
    final harness = _Harness(queueEntry: entry, rows: [entry]);
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.tap(find.text('发布'));
    await tester.pump();
    expect(harness.bloc.events.single, isA<UploadBlogEvent>());

    harness.states.add(BlogUploadSuccess());
    await tester.pumpAndSettle();

    expect(harness.queue.removed, [entry.id]);
    expect(harness.queue.enqueued, isEmpty);
  });

  testWidgets('a resumed publish that is queued again retires the old entry', (
    tester,
  ) async {
    final entry = queueEntry();
    final harness = _Harness(queueEntry: entry, rows: [entry]);
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.tap(find.text('发布'));
    await tester.pump();
    harness.states.add(
      const BlogUploadFailure(
        Failure(
          '无法连接到网络，请检查网络设置',
          kind: FailureKind.network,
          code: 'network.unavailable',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.queue.enqueued, hasLength(1));
    // The text changed, so the replacement must not reuse the old intent key:
    // the server would replay the original article instead of creating this one.
    expect(
      harness.queue.enqueued.single.idempotencyKey,
      isNot(entry.idempotencyKey),
    );
    expect(harness.queue.removed, [entry.id]);
  });

  testWidgets('a fresh editor never touches the queue', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.enterText(find.byType(TextFormField).first, '另一篇');
    await tester.enterText(find.byType(EditorBodyField), '正文');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pump();
    harness.states.add(
      const BlogUploadFailure(
        Failure(
          '无法连接到网络，请检查网络设置',
          kind: FailureKind.network,
          code: 'network.unavailable',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.queue.enqueued, hasLength(1));
    expect(harness.queue.removed, isEmpty);
  });

  testWidgets('a failed update is queued against the article it edits', (
    tester,
  ) async {
    final harness = _Harness(blog: publishedBlog());
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.enterText(find.byType(TextFormField).first, '改过的标题');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pump();
    expect(harness.bloc.events.single, isA<UpdateBlogEvent>());

    harness.states.add(
      const BlogUploadFailure(
        Failure(
          '无法连接到网络，请检查网络设置',
          kind: FailureKind.network,
          code: 'network.unavailable',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.queue.enqueued, hasLength(1));
    final queued = harness.queue.enqueued.single;
    expect(queued.kind, PublishQueueKind.edit);
    expect(queued.targetId, 'my-slug');
    expect(queued.title, '改过的标题');
  });

  testWidgets('a queued edit resumes as an update of that article', (
    tester,
  ) async {
    final entry = queueEntry(
      kind: PublishQueueKind.edit,
      targetId: 'my-slug',
      title: '待更新标题',
      content: '待更新正文',
    );
    final harness = _Harness(queueEntry: entry, rows: [entry]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    // Update mode, not a new article: publishing must not create a second one.
    expect(find.text(l10n.editorEditTitle), findsOneWidget);
    expect(find.text(l10n.editorNewTitle), findsNothing);
    expect(titleText(tester), '待更新标题');

    await tester.tap(find.text('发布'));
    await tester.pump();
    final event = harness.bloc.events.single;
    expect(event, isA<UpdateBlogEvent>());
    expect((event as UpdateBlogEvent).blogId, 'my-slug');

    harness.states.add(BlogUploadSuccess());
    await tester.pumpAndSettle();
    expect(harness.queue.removed, [entry.id]);
  });

  testWidgets('a resumed edit keeps every category it was queued with', (
    tester,
  ) async {
    final entry = queueEntry(
      kind: PublishQueueKind.edit,
      targetId: 'my-slug',
      categoryIds: const ['cat-1', 'cat-2'],
    );
    final harness = _Harness(
      queueEntry: entry,
      rows: [entry],
      getCategories: GetCategories(
        _Catalog(const [
          CategoryRef(id: 'cat-1', slug: 'essay', name: '随笔'),
          CategoryRef(id: 'cat-2', slug: 'poem', name: '诗'),
        ]),
      ),
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);

    // Both chips come back selected, not just the first one: the entry stores
    // the whole list, and an edit that resumed with one would drop the other on
    // the next save.
    for (final label in ['随笔', '诗']) {
      final chip = tester.widget<InputChip>(
        find.ancestor(of: find.text(label), matching: find.byType(InputChip)),
      );
      expect(chip.selected, isTrue);
    }

    await tester.tap(find.text('发布'));
    await tester.pump();
    expect((harness.bloc.events.single as UpdateBlogEvent).categoryIds, [
      'cat-1',
      'cat-2',
    ]);
  });

  testWidgets('a selected media-library cover is sent and retained when queued', (
    tester,
  ) async {
    const coverUrl =
        'https://api.example.invalid/api/v1/media/64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01';
    final repository = _MockMediaUserRepository();
    final asset = UserMediaAsset(
      id: '64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01',
      imageUrl: coverUrl,
      width: 1200,
      height: 800,
      byteSize: 4096,
      createdAt: DateTime.utc(2026, 10, 28),
    );
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: any(named: 'sessionFence'),
        cursor: null,
      ),
    ).thenAnswer(
      (_) async => right(UserMediaPage(items: [asset], nextCursor: null)),
    );
    final harness = _Harness(
      getUserMediaLibraryPage: GetUserMediaLibraryPage(repository),
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await tester.tap(find.text(l10n.editorCoverChooseFromLibrary));
    await tester.pumpAndSettle();
    expect(find.text(l10n.userMediaPickerTitle), findsOneWidget);
    expect(find.text('1200 × 800'), findsOneWidget);
    await tester.tap(find.text('1200 × 800'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Reuse cover');
    await tester.enterText(find.byType(EditorBodyField), 'Article body');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pump();

    final event = harness.bloc.events.single as UploadBlogEvent;
    expect(event.image, isNull);
    expect(event.uploadedCoverUrl, coverUrl);

    harness.states.add(
      const BlogUploadFailure(
        Failure(
          '无法连接到网络，请检查网络设置',
          kind: FailureKind.network,
          code: 'network.unavailable',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.queue.enqueued, hasLength(1));
    expect(harness.queue.enqueued.single.coverUrl, coverUrl);
    expect(harness.queue.enqueued.single.coverFileName, isNull);
    final capturedFence =
        verify(
              () => repository.getMediaLibraryPage(
                sessionFence: captureAny(named: 'sessionFence'),
                cursor: null,
              ),
            ).captured.single
            as NowaveSessionFence;
    expect(capturedFence.userId, 'user');
    expect(capturedFence.generation, 1);
  });

  testWidgets('a session change clears and closes the media picker', (
    tester,
  ) async {
    final repository = _MockMediaUserRepository();
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: any(named: 'sessionFence'),
        cursor: null,
      ),
    ).thenAnswer(
      (_) async => right(UserMediaPage(items: [], nextCursor: null)),
    );
    final harness = _Harness(
      getUserMediaLibraryPage: GetUserMediaLibraryPage(repository),
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    await tester.tap(find.text(l10n.editorCoverChooseFromLibrary));
    await tester.pumpAndSettle();
    expect(find.text(l10n.userMediaPickerTitle), findsOneWidget);

    harness.identity.userId = null;
    harness.identity.controller.add(null);
    await tester.pumpAndSettle();

    expect(find.text(l10n.userMediaPickerTitle), findsNothing);
    expect(find.text(l10n.editorSessionChanged), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a queued media-library cover is reused by the editor', (
    tester,
  ) async {
    const coverUrl =
        'https://api.example.invalid/api/v1/media/64f7a2c6-42b6-4b7b-9f89-2d68b8c45a01';
    final entry = queueEntry(
      title: 'Queued media cover',
      content: 'Queued body',
      coverUrl: coverUrl,
    );
    final harness = _Harness(queueEntry: entry, rows: [entry]);
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.tap(find.text('发布'));
    await tester.pump();

    final event = harness.bloc.events.single as UploadBlogEvent;
    expect(event.image, isNull);
    expect(event.uploadedCoverUrl, coverUrl);
  });
}
