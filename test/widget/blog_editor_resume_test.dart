import 'dart:async';
import 'dart:convert';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/editor_body_field.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
    List<PublishQueueEntry> rows = const [],
    ImageUpload? cover,
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
            queueEntry: queueEntry,
            draftStore: drafts,
            sessionIdentity: identity,
            publishQueueStore: queue,
            publishQueueDrainer: drainer,
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
}
