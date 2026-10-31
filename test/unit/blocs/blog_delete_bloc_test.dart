import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements BlogRepository {}

void main() {
  test('a false delete result is not displayed as success', () async {
    final repository = _Repository();
    when(
      () => repository.deleteBlog('slug'),
    ).thenAnswer((_) async => right(false));
    final bloc = BlogUploadBloc(
      uploadBlog: UploadBlog(repository),
      updateBlog: UpdateBlog(repository),
      deleteBlog: DeleteBlog(repository),
    );
    addTearDown(bloc.close);

    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<BlogDeleteLoading>(),
        isA<BlogUploadFailure>().having(
          (state) => state.failure.code,
          'code',
          'article.deleteFailed',
        ),
      ]),
    );
    bloc.add(const DeleteBlogEvent(blogId: 'slug'));
    await states;
  });
}
