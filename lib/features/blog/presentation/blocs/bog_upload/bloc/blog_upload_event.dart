part of 'blog_upload_bloc.dart';

abstract class BlogUploadEvent extends Equatable {
  const BlogUploadEvent();
}

class UploadBlogEvent extends BlogUploadEvent {
  final File image;
  final String title;
  final String content;
  final String posterId;
  final List<String> tags;

  /// MIME type reported by the picker; uploaded as the object's
  /// contentType.
  final String? imageMimeType;

  const UploadBlogEvent({
    required this.image,
    required this.title,
    required this.content,
    required this.posterId,
    required this.tags,
    this.imageMimeType,
  });

  @override
  List<Object?> get props => [
        image,
        title,
        content,
        posterId,
        tags,
        imageMimeType,
      ];
}

class UpdateBlogEvent extends BlogUploadEvent {
  final String blogId;
  final File? image; // Optional, only if updating image
  final String title;
  final String content;
  final List<String> tags;

  /// MIME type reported by the picker; uploaded as the object's
  /// contentType.
  final String? imageMimeType;

  const UpdateBlogEvent({
    required this.blogId,
    this.image,
    required this.title,
    required this.content,
    required this.tags,
    this.imageMimeType,
  });

  @override
  List<Object?> get props => [
        blogId,
        image,
        title,
        content,
        tags,
        imageMimeType,
      ];
}

class DeleteBlogEvent extends BlogUploadEvent {
  final String blogId;

  const DeleteBlogEvent({required this.blogId});

  @override
  List<Object> get props => [blogId];
}
