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

  const UploadBlogEvent({
    required this.image,
    required this.title,
    required this.content,
    required this.posterId,
    required this.tags,
    required this.sessionFence,
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
  ];
}

class UpdateBlogEvent extends BlogUploadEvent {
  final String blogId;
  final ImageUpload? image; // Optional, only if updating image
  final String title;
  final String content;
  final List<String> tags;
  final NowaveSessionFence sessionFence;

  const UpdateBlogEvent({
    required this.blogId,
    this.image,
    required this.title,
    required this.content,
    required this.tags,
    required this.sessionFence,
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
  ];
}

class DeleteBlogEvent extends BlogUploadEvent {
  final String blogId;

  const DeleteBlogEvent({required this.blogId});

  @override
  List<Object> get props => [blogId];
}
