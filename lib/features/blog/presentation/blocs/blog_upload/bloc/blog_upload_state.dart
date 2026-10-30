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
  final String error;

  const BlogUploadFailure(this.error);

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
