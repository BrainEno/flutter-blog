import 'dart:io';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

class UpdateBlog implements UseCase<Blog, UpdateBlogParams> {
  final BlogRepository blogRepository;
  const UpdateBlog(this.blogRepository);

  @override
  Future<Either<Failure, Blog>> call(UpdateBlogParams params) async {
    return await blogRepository.editBlog(
        blogId: params.blogId,
        image: params.image,
        title: params.title,
        content: params.content,
        tags: params.tags,
        imageMimeType: params.imageMimeType);
  }
}

class UpdateBlogParams {
  final String blogId;
  final File? image;
  final String title;
  final String content;
  final List<String> tags;
  final String? imageMimeType;

  UpdateBlogParams({
    required this.blogId,
    this.image,
    required this.title,
    required this.content,
    required this.tags,
    this.imageMimeType,
  });
}
