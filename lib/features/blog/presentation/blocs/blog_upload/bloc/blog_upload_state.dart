part of 'blog_upload_bloc.dart';

abstract class BlogUploadState extends Equatable {
  const BlogUploadState();
}

class BlogUploadInitial extends BlogUploadState {
  @override
  List<Object> get props => [];
}

class BlogUploadLoading extends BlogUploadState {
  @override
  List<Object> get props => [];
}

class BlogUploadSuccess extends BlogUploadState {
  @override
  List<Object> get props => [];
}

class BlogUploadFailure extends BlogUploadState {
  final Failure failure;

  const BlogUploadFailure(this.failure);

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get error => failure.message;

  @override
  List<Object> get props => [error];
}

class BlogDeleteLoading extends BlogUploadState {
  @override
  List<Object> get props => [];
}

class BlogDeleteSuccess extends BlogUploadState {
  @override
  List<Object> get props => [];
}
