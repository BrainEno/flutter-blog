part of 'blog_upload_bloc.dart';

abstract class BlogUploadEvent extends Equatable {
  const BlogUploadEvent();
}

class UploadBlogEvent extends BlogUploadEvent {
  /// Picked cover; null publishes a text-only article (issue #17).
  final ImageUpload? image;

  /// An existing immutable media asset selected from the user's library.
  final String? uploadedCoverUrl;
  final String title;
  final String content;
  final String posterId;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// Stable per publish intent (issue #23); the editor keeps it so a failure
  /// can be queued and retried without creating a second article.
  final String? idempotencyKey;

  /// The author's category choice; null leaves the field out of the request.
  final List<String>? categoryIds;

  /// The author's summary; null or blank lets the server write one.
  final String? summary;

  /// False stores a private draft instead of publishing.
  final bool publish;

  const UploadBlogEvent({
    required this.image,
    this.uploadedCoverUrl,
    required this.title,
    required this.content,
    required this.posterId,
    required this.tags,
    required this.sessionFence,
    this.idempotencyKey,
    this.categoryIds,
    this.summary,
    this.publish = true,
  });

  @override
  List<Object?> get props => [
    image,
    uploadedCoverUrl,
    title,
    content,
    posterId,
    tags,
    sessionFence.userId,
    sessionFence.generation,
    idempotencyKey,
    categoryIds,
    summary,
    publish,
  ];
}

class UpdateBlogEvent extends BlogUploadEvent {
  final String blogId;

  /// Original/rebased server revision for the conditional PUT. This is
  /// intentionally required: an editor without it must retain the draft and
  /// ask for a refresh rather than falling back to the old unconditional PUT.
  final ArticleRevision expectedRevision;
  final ImageUpload? image; // Optional, only if updating image

  /// An existing immutable media asset selected from the user's library.
  final String? uploadedCoverUrl;
  final String title;
  final String content;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// The edition being edited (the opened article's `locale`). The server
  /// replaces exactly this translation, so it must not be guessed from the
  /// interface language.
  final String? locale;

  /// The author's category choice; null leaves the article's categories as
  /// they are.
  final List<String>? categoryIds;

  /// The rewritten summary; null keeps the server's own.
  final String? summary;

  /// False keeps the article (or takes it back to) a private draft.
  final bool publish;

  const UpdateBlogEvent({
    required this.blogId,
    required this.expectedRevision,
    this.image,
    this.uploadedCoverUrl,
    required this.title,
    required this.content,
    required this.tags,
    required this.sessionFence,
    this.locale,
    this.categoryIds,
    this.summary,
    this.publish = true,
  });

  @override
  List<Object?> get props => [
    blogId,
    expectedRevision,
    image,
    uploadedCoverUrl,
    title,
    content,
    tags,
    sessionFence.userId,
    sessionFence.generation,
    locale,
    categoryIds,
    summary,
    publish,
  ];
}

class DeleteBlogEvent extends BlogUploadEvent {
  final String blogId;

  const DeleteBlogEvent({required this.blogId});

  @override
  List<Object> get props => [blogId];
}
