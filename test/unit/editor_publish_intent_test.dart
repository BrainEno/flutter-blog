import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/editor/editor_publish_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPublishQueueStore extends Mock implements PublishQueueStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  final draft = BlogDraft(
    userId: 'author',
    title: ' Title ',
    content: ' Body ',
    tags: const ['news'],
    categoryIds: const ['category-1'],
    updatedAt: DateTime.utc(2026),
  );

  Blog article() => Blog(
    id: 'article-slug',
    title: 'Old',
    content: 'Old body',
    posterId: 'author',
    imageUrl: '',
    tags: const [],
    locale: 'en',
    updatedAt: DateTime.utc(2026),
  );

  EditorPublishIntent createIntent({Blog? target, ArticleRevision? revision}) =>
      EditorPublishIntent(
        draft: draft,
        target: target,
        expectedRevision: revision,
        image: null,
        coverUrl: 'https://example.test/media/cover.webp',
        sessionGeneration: 7,
        idempotencyKey: 'publish-key',
      );

  group('EditorPublishIntent', () {
    test('creates an upload event from its immutable snapshot', () {
      final event = createIntent().buildEvent();

      expect(event, isA<UploadBlogEvent>());
      final upload = event as UploadBlogEvent;
      expect(upload.title, 'Title');
      expect(upload.content, 'Body');
      expect(upload.posterId, 'author');
      expect(upload.sessionFence.userId, 'author');
      expect(upload.sessionFence.generation, 7);
      expect(upload.idempotencyKey, 'publish-key');
      expect(upload.categoryIds, const ['category-1']);
    });

    test('keeps article locale and revision on an update', () {
      final revision = ArticleRevision.parse('9007199254740993')!;
      final event = createIntent(
        target: article(),
        revision: revision,
      ).buildEvent();

      expect(event, isA<UpdateBlogEvent>());
      final update = event as UpdateBlogEvent;
      expect(update.blogId, 'article-slug');
      expect(update.locale, 'en');
      expect(update.expectedRevision, revision);
    });

    test('refuses an update with no conditional revision', () {
      final intent = createIntent(target: article());

      expect(intent.canDispatch, isFalse);
      expect(intent.buildEvent, throwsStateError);
    });

    test(
      'queues exactly the update snapshot after an uncertain failure',
      () async {
        final revision = ArticleRevision.parse('42')!;
        final intent = createIntent(target: article(), revision: revision);
        final store = _MockPublishQueueStore();
        when(
          () => store.enqueue(
            userId: any(named: 'userId'),
            title: any(named: 'title'),
            content: any(named: 'content'),
            tags: any(named: 'tags'),
            idempotencyKey: any(named: 'idempotencyKey'),
            cover: any(named: 'cover', that: isNull),
            coverUrl: any(named: 'coverUrl'),
            kind: any(named: 'kind'),
            targetId: any(named: 'targetId'),
            categoryIds: any(named: 'categoryIds'),
            expectedRevision: any(named: 'expectedRevision'),
            locale: any(named: 'locale'),
          ),
        ).thenAnswer((_) async => throw UnimplementedError());

        await expectLater(intent.enqueue(store), throwsUnimplementedError);
        verify(
          () => store.enqueue(
            userId: 'author',
            title: 'Title',
            content: 'Body',
            tags: any(named: 'tags'),
            idempotencyKey: 'publish-key',
            cover: null,
            coverUrl: 'https://example.test/media/cover.webp',
            kind: PublishQueueKind.edit,
            targetId: 'article-slug',
            categoryIds: any(named: 'categoryIds'),
            expectedRevision: revision,
            locale: 'en',
          ),
        ).called(1);
      },
    );

    test('only transient failures can be queued', () {
      expect(EditorPublishIntent.shouldQueue(Failure.networkOffline()), isTrue);
      expect(
        EditorPublishIntent.shouldQueue(Failure.auth('sign in again')),
        isFalse,
      );
      expect(
        EditorPublishIntent.shouldQueue(
          const Failure('invalid', kind: FailureKind.validation),
        ),
        isFalse,
      );
    });
  });
}
