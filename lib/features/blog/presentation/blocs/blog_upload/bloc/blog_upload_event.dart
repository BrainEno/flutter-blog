part of 'blog_upload_bloc.dart';

abstract class BlogUploadEvent extends Equatable {
  const BlogUploadEvent();
}

class UploadBlogEvent extends BlogUploadEvent {
  /// Picked cover; null publishes a text-only article (issue #17).
  final ImageUpload? image;
  final String title;
  final String content;
  final String posterId;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// Stable per publish intent (issue #23); the editor keeps it so a failure
  /// can be queued and retried without creating a second article.
  final String? idempotencyKey;

  const UploadBlogEvent({
    required this.image,
    required this.title,
    required this.content,
    required this.posterId,
    required this.tags,
    required this.sessionFence,
    this.idempotencyKey,
  });

  @override
  List<Object?> get props => [
    image,
    title,
    content,
    posterId,
    tags,
    sessionFence.userId,
    sessionFence.generation,
    idempotencyKey,
  ];
}

class UpdateBlogEvent extends BlogUploadEvent {
  final String blogId;
  final ImageUpload? image; // Optional, only if updating image
  final String title;
  final String content;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  /// The edition being edited (the opened article's `locale`). The server
  /// replaces exactly this translation, so it must not be guessed from the
  /// interface language.
  final String? locale;

  const UpdateBlogEvent({
    required this.blogId,
    this.image,
    required this.title,
    required this.content,
    required this.tags,
    required this.sessionFence,
    this.locale,
  });

  @override
  List<Object?> get props => [
    blogId,
    image,
    title,
    content,
    tags,
    sessionFence.userId,
    sessionFence.generation,
    locale,
  ];
}

class DeleteBlogEvent extends BlogUploadEvent {
  final String blogId;

  const DeleteBlogEvent({required this.blogId});

  @override
  List<Object> get props => [blogId];
}
