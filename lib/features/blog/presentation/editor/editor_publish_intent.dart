import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';

/// One immutable request to publish or conditionally update an article.
///
/// The editor owns controllers and user interaction; this value owns the
/// snapshot that crosses the asynchronous publish boundary. That separation is
/// important because a user can continue typing while media upload or the
/// server request is in flight. Every retry, queue row, and BLoC event below
/// is therefore derived from the same text, cover, category choice, revision,
/// locale, and session generation.
///
/// A new instance must be made for each button press. Reusing an old intent
/// after a successful publish would incorrectly reuse its idempotency key.
class EditorPublishIntent {
  const EditorPublishIntent({
    required this.draft,
    required this.target,
    required this.expectedRevision,
    required this.image,
    required this.coverUrl,
    required this.sessionGeneration,
    required this.idempotencyKey,
    this.publish = true,
  });

  /// The durable text snapshot saved before any network request begins.
  final BlogDraft draft;

  /// Null means create; a non-null target means a conditional update.
  final Blog? target;

  /// The opaque server condition from when the editor opened or explicitly
  /// rebased. Updates without it must stay local rather than becoming an
  /// unsafe unconditional PUT.
  final ArticleRevision? expectedRevision;

  /// Raw local bytes selected for this intent. These are owned by the queue
  /// when a retry is stored, not by the image picker file preview.
  final ImageUpload? image;

  /// An immutable media-library cover, if the author chose one. It is mutually
  /// exclusive with [image] in normal UI flows, but both fields are retained
  /// so a caller never has to reconstruct a failure snapshot.
  final String? coverUrl;

  /// Captured with the editor, not read lazily after an await.
  final int sessionGeneration;

  /// Stable for this exact create intent; the server uses it to replay a lost
  /// response without creating a duplicate article.
  final String idempotencyKey;

  /// False stores a private draft on the server (or takes a published article
  /// back to one) instead of publishing.
  final bool publish;

  bool get isUpdate => target != null;

  PublishQueueKind get queueKind =>
      isUpdate ? PublishQueueKind.edit : PublishQueueKind.create;

  NowaveSessionFence get sessionFence =>
      NowaveSessionFence(userId: draft.userId, generation: sessionGeneration);

  /// Whether this value can ever be translated into a safe remote write.
  bool get canDispatch => !isUpdate || expectedRevision != null;

  /// The presentation event consumed by [BlogUploadBloc].
  ///
  /// Throws instead of inventing an update condition. The page normally checks
  /// [canDispatch] first to explain the problem to the author; this guard
  /// protects future entry points such as keyboard shortcuts and deep links.
  BlogUploadEvent buildEvent() {
    final article = target;
    if (article == null) {
      return UploadBlogEvent(
        image: image,
        uploadedCoverUrl: coverUrl,
        title: draft.title.trim(),
        content: draft.content.trim(),
        posterId: draft.userId,
        tags: List<String>.unmodifiable(draft.tags),
        sessionFence: sessionFence,
        idempotencyKey: idempotencyKey,
        categoryIds: _copyCategories(draft.categoryIds),
        summary: draft.summary?.trim(),
        publish: publish,
      );
    }
    final revision = expectedRevision;
    if (revision == null) {
      throw StateError('A conditional article update requires a revision.');
    }
    return UpdateBlogEvent(
      blogId: article.id,
      expectedRevision: revision,
      image: image,
      uploadedCoverUrl: coverUrl,
      title: draft.title.trim(),
      content: draft.content.trim(),
      tags: List<String>.unmodifiable(draft.tags),
      sessionFence: sessionFence,
      // This is the edition that was opened, not the current display locale.
      locale: article.locale,
      categoryIds: _copyCategories(draft.categoryIds),
      summary: draft.summary?.trim(),
      publish: publish,
    );
  }

  /// Persists precisely this request for a future retry.
  ///
  /// The store writes local cover bytes before returning. A caller may retire a
  /// predecessor queue row only after this future completes successfully,
  /// which prevents a failed edit from losing its only copy between retries.
  Future<PublishQueueEntry> enqueue(PublishQueueStore store) {
    final article = target;
    final revision = expectedRevision;
    if (article != null && revision == null) {
      throw StateError('A queued article update requires a revision.');
    }
    return store.enqueue(
      userId: draft.userId,
      title: draft.title.trim(),
      content: draft.content.trim(),
      tags: List<String>.unmodifiable(draft.tags),
      idempotencyKey: idempotencyKey,
      cover: image,
      coverUrl: coverUrl,
      kind: queueKind,
      targetId: article?.id,
      categoryIds: _copyCategories(draft.categoryIds),
      expectedRevision: article == null ? null : revision,
      // A queue may run days later while the app displays another language.
      locale: article?.locale,
      summary: draft.summary?.trim(),
      publish: publish,
    );
  }

  /// Transport/server failures may become a durable retry. Auth, permission,
  /// validation and storage failures need an explicit human or device action,
  /// so queueing them would create a misleading perpetually-failing row.
  static bool shouldQueue(Failure failure) => switch (failure.kind) {
    FailureKind.network ||
    FailureKind.timeout ||
    FailureKind.server ||
    FailureKind.unknown => true,
    _ => false,
  };

  static List<String>? _copyCategories(List<String>? categories) =>
      categories == null ? null : List<String>.unmodifiable(categories);
}
