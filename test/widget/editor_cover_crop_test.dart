import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/media/cover_crop.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/cover_crop_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

/// A 1x1 transparent PNG: the picked "photo", decodable by the preview.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUA'
  'Aen63NgAAAAASUVORK5CYII=',
);

/// What the fake codec answers for a cut: the same PNG under a new identity,
/// so the preview still decodes while the test can tell it from the source.
final _cutBytes = Uint8List.fromList(_pngBytes);

final _revision = ArticleRevision.parse('7')!;

class _RecordingUploadBloc extends Mock implements BlogUploadBloc {
  final List<BlogUploadEvent> events = [];

  @override
  void add(BlogUploadEvent event) => events.add(event);
}

class _FakeDraftStore implements BlogDraftStore {
  @override
  Future<BlogDraft?> load(String? blogId, {required String userId}) async =>
      null;

  @override
  Future<void> save(BlogDraft draft) async {}

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

class _NoCategories implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryRef>>> listCategories() async =>
      right(const []);

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
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => 'user';
  @override
  String? get accessToken => 'synthetic-token';
  @override
  int get sessionGeneration => 1;
  @override
  Stream<void> get identityChanges => _changes.stream;

  void dispose() => _changes.close();
}

class _FakeCropper extends CoverCropper {
  _FakeCropper({this.readable = true});

  final bool readable;
  final List<CoverCropRequest> requests = [];
  final List<Uint8List> prepared = [];

  @override
  Future<CoverSource?> prepare(Uint8List bytes) async {
    prepared.add(bytes);
    if (!readable) return null;
    return CoverSource(bytes: bytes, width: 1600, height: 1200);
  }

  @override
  Future<Uint8List?> crop(CoverCropRequest request) async {
    requests.add(request);
    return _cutBytes;
  }
}

Blog _article() => BlogModel(
  id: 'a-slug',
  articleId: 'article-a-slug',
  articleRevision: _revision,
  title: '已发布标题',
  content: '已发布正文',
  summary: '摘要',
  serverSummary: '摘要',
  posterId: 'user',
  imageUrl: 'https://example.invalid/cover.webp',
  tags: const [],
  updatedAt: DateTime.utc(2025),
);

Future<_RecordingUploadBloc> _openEditor(
  WidgetTester tester,
  _FakeCropper cropper, {
  Blog? blog,
  bool pickFails = false,
}) async {
  final bloc = _RecordingUploadBloc();
  when(() => bloc.state).thenReturn(BlogUploadInitial());
  when(
    () => bloc.stream,
  ).thenAnswer((_) => const Stream<BlogUploadState>.empty());
  final user = AppUserCubit()
    ..updateUser(
      User(
        id: 'user',
        email: 'user@example.invalid',
        name: 'Synthetic user',
        updatedAt: DateTime.utc(2024),
      ),
    );
  final session = _FakeSession();
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
          draftStore: _FakeDraftStore(),
          sessionIdentity: session,
          getCategories: GetCategories(_NoCategories()),
          pickCoverImage: () async {
            if (pickFails) throw const PickImageException('denied');
            return PickedImage(
              file: File('never-read.png'),
              bytes: _pngBytes,
              mimeType: 'image/png',
            );
          },
          coverCropper: cropper,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _writeArticle(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('editor-title-field')),
      matching: find.byType(EditableText),
    ),
    '标题',
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('editor-body-field')),
      matching: find.byType(EditableText),
    ),
    '正文',
  );
  await tester.pump();
}

final _cover = find.byKey(const Key('editor-cover-bytes'));

/// The bytes behind the cover preview, through the decode-size wrapper.
Uint8List _previewBytes(WidgetTester tester) {
  var provider = tester.widget<Image>(_cover).image;
  if (provider is ResizeImage) provider = provider.imageProvider;
  return (provider as MemoryImage).bytes;
}

void main() {
  testWidgets('a picked photo is framed, then published as the cut', (
    tester,
  ) async {
    final cropper = _FakeCropper();
    final bloc = await _openEditor(tester, cropper);
    expect(find.text('选择图片'), findsOneWidget);
    expect(find.byKey(const Key('editor-cover-recrop')), findsNothing);
    expect(find.byKey(const Key('editor-cover-clear')), findsNothing);

    await _tapKey(tester, 'editor-cover-pick');
    expect(find.byType(CoverCropPage), findsOneWidget);
    expect(find.text('裁剪封面'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    expect(find.byType(CoverCropPage), findsNothing);
    expect(cropper.prepared.single, same(_pngBytes));
    expect(_previewBytes(tester), same(_cutBytes));
    expect(find.text('更换图片'), findsOneWidget);
    expect(find.text('调整裁剪'), findsOneWidget);
    // A new piece has no earlier cover to fall back to.
    expect(find.text('移除封面'), findsOneWidget);

    await _writeArticle(tester);
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    final event = bloc.events.single as UploadBlogEvent;
    expect(event.image!.bytes, same(_cutBytes));
    expect(event.image!.mimeType, 'image/jpeg');
    expect(event.uploadedCoverUrl, isNull);
  });

  testWidgets('adjusting reframes the uncut photo where the frame was', (
    tester,
  ) async {
    final cropper = _FakeCropper();
    await _openEditor(tester, cropper);
    await _tapKey(tester, 'editor-cover-pick');
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();
    final first = cropper.requests.single.rect;

    await _tapKey(tester, 'editor-cover-recrop');
    expect(find.byType(CoverCropPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    // The second cut starts from the original, not from the first cut.
    expect(cropper.prepared, hasLength(2));
    expect(cropper.prepared.last, same(_pngBytes));
    final second = cropper.requests.last.rect;
    expect(second.left, closeTo(first.left, 1e-6));
    expect(second.top, closeTo(first.top, 1e-6));
    expect(second.width, closeTo(first.width, 1e-6));
  });

  testWidgets('backing out of the frame keeps the earlier cover', (
    tester,
  ) async {
    final cropper = _FakeCropper();
    await _openEditor(tester, cropper);
    await _tapKey(tester, 'editor-cover-pick');
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    await _tapKey(tester, 'editor-cover-pick');
    await tester.tap(find.byKey(const Key('cover-crop-cancel')));
    await tester.pumpAndSettle();

    expect(cropper.requests, hasLength(1));
    expect(_cover, findsOneWidget);
    expect(find.text('调整裁剪'), findsOneWidget);
  });

  testWidgets('removing the cover of a new piece publishes none', (
    tester,
  ) async {
    final cropper = _FakeCropper();
    final bloc = await _openEditor(tester, cropper);
    await _tapKey(tester, 'editor-cover-pick');
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    await _tapKey(tester, 'editor-cover-clear');

    expect(_cover, findsNothing);
    expect(find.text('选择图片'), findsOneWidget);
    expect(find.byKey(const Key('editor-cover-clear')), findsNothing);
    await _writeArticle(tester);
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect((bloc.events.single as UploadBlogEvent).image, isNull);
  });

  testWidgets('an article goes back to its own cover', (tester) async {
    final cropper = _FakeCropper();
    final bloc = await _openEditor(tester, cropper, blog: _article());
    expect(find.text('更换图片'), findsOneWidget);
    await _tapKey(tester, 'editor-cover-pick');
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    expect(find.text('恢复原封面'), findsOneWidget);
    await _tapKey(tester, 'editor-cover-clear');
    expect(_cover, findsNothing);

    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    final event = bloc.events.single as UpdateBlogEvent;
    // No cover in the write: the server keeps the one it has.
    expect(event.image, isNull);
    expect(event.uploadedCoverUrl, isNull);
  });

  testWidgets('a photo the codec cannot read is used uncut', (tester) async {
    final cropper = _FakeCropper(readable: false);
    final bloc = await _openEditor(tester, cropper);

    await _tapKey(tester, 'editor-cover-pick');

    expect(find.byType(CoverCropPage), findsNothing);
    expect(find.text('这张图片无法裁剪，已按原图使用'), findsOneWidget);
    expect(_cover, findsOneWidget);
    // Nothing to reframe, but the choice can still be undone.
    expect(find.byKey(const Key('editor-cover-recrop')), findsNothing);
    expect(find.byKey(const Key('editor-cover-clear')), findsOneWidget);

    await _writeArticle(tester);
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    final event = bloc.events.single as UploadBlogEvent;
    expect(event.image!.bytes, same(_pngBytes));
    expect(_previewBytes(tester), same(_pngBytes));
    expect(event.image!.mimeType, 'image/png');
  });

  testWidgets('a failed pick says so and opens no frame', (tester) async {
    final cropper = _FakeCropper();
    await _openEditor(tester, cropper, pickFails: true);

    await _tapKey(tester, 'editor-cover-pick');

    expect(find.byType(CoverCropPage), findsNothing);
    expect(find.text('选择图片失败，请重试'), findsOneWidget);
    expect(cropper.prepared, isEmpty);
  });
}
