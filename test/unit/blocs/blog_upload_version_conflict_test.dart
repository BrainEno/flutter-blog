import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
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
  final revision = ArticleRevision.parse('9223372036854775807')!;
  const fence = NowaveSessionFence(userId: 'author', generation: 2);

  setUpAll(() {
    registerFallbackValue(revision);
    registerFallbackValue(fence);
    registerFallbackValue(<String>[]);
  });

  test('an update conflict gets the draft-preserving upload state', () async {
    final repository = _Repository();
    when(
      () => repository.editBlog(
        blogId: any(named: 'blogId'),
        expectedRevision: any(named: 'expectedRevision'),
        title: any(named: 'title'),
        content: any(named: 'content'),
        tags: any(named: 'tags'),
        image: any(named: 'image'),
        uploadedCoverUrl: any(named: 'uploadedCoverUrl'),
        locale: any(named: 'locale'),
        sessionFence: any(named: 'sessionFence'),
        categoryIds: any(named: 'categoryIds'),
      ),
    ).thenAnswer(
      (_) async => left(
        const Failure(
          '文章已在其他位置更新，请先核对最新内容',
          kind: FailureKind.validation,
          code: 'article.versionConflict',
        ),
      ),
    );
    final bloc = BlogUploadBloc(
      uploadBlog: UploadBlog(repository),
      updateBlog: UpdateBlog(repository),
      deleteBlog: DeleteBlog(repository),
    );
    addTearDown(bloc.close);

    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<BlogUploadLoading>(),
        isA<BlogUploadVersionConflict>().having(
          (state) => state.failure.code,
          'code',
          'article.versionConflict',
        ),
      ]),
    );

    bloc.add(
      UpdateBlogEvent(
        blogId: 'article-slug',
        expectedRevision: revision,
        title: 'local title',
        content: 'local body',
        tags: const ['draft'],
        sessionFence: fence,
      ),
    );

    await states;
  });
}
