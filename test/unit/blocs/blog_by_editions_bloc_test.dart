import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class _Editions implements GetMyArticleEditions {
  _Editions(this.handler);

  final Future<Either<Failure, ArticleEditions>> Function(
    GetMyArticleEditionsParams,
  )
  handler;

  @override
  Future<Either<Failure, ArticleEditions>> call(
    GetMyArticleEditionsParams params,
  ) => handler(params);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SingleList implements GetMyArticles {
  _SingleList(this.handler);

  final Future<Either<Failure, List<Blog>>> Function(GetMyArticlesParams)
  handler;

  @override
  Future<Either<Failure, List<Blog>>> call(GetMyArticlesParams params) =>
      handler(params);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ByPoster implements GetBlogsByPoster {
  @override
  Future<Either<Failure, List<Blog>>> call(
    GetBlogsByPosterParams params,
  ) async => right(const <Blog>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Blog _blog(String id, String locale) => Blog(
  id: id,
  posterId: 'poster',
  title: 'title $id',
  content: 'content',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime(2024),
  locale: locale,
);

BlogByBloc _bloc(Future<Either<Failure, ArticleEditions>> Function() load) {
  return BlogByBloc(
    getBlogsByPoster: _ByPoster(),
    getMyArticles: _SingleList((_) async => right(const <Blog>[])),
    getMyArticleEditions: _Editions((_) => load()),
  );
}

void main() {
  test('emits every edition the server confirmed it read', () async {
    final bloc = _bloc(
      () async => right(
        ArticleEditions(
          blogs: [_blog('essay', 'zh-CN'), _blog('essay', 'en')],
          locales: const ['zh-CN', 'zh-TW', 'en'],
        ),
      ),
    );
    addTearDown(bloc.close);
    final states = <BlogByState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    bloc.add(GetMyArticleEditionsEvent(userId: 'u1'));
    await bloc.stream.firstWhere(
      (state) => state is GetMyArticleEditionsSuccess,
    );

    final success = states.whereType<GetMyArticleEditionsSuccess>().single;
    expect(success.blogs.map((blog) => blog.locale), ['zh-CN', 'en']);
    expect(success.editions.isConfirmed, isTrue);
    expect(states.first, isA<GetBlogsByUserLoading>());
  });

  test('an older deployment keeps the list unconfirmed', () async {
    final bloc = _bloc(
      () async => right(
        ArticleEditions(blogs: [_blog('essay', 'zh-CN')], locales: null),
      ),
    );
    addTearDown(bloc.close);

    bloc.add(GetMyArticleEditionsEvent(userId: 'u1'));
    final state = await bloc.stream.firstWhere(
      (state) => state is GetMyArticleEditionsSuccess,
    );

    final success = state as GetMyArticleEditionsSuccess;
    expect(success.editions.isConfirmed, isFalse);
  });

  test('a failure is reported, never an empty archive', () async {
    final bloc = _bloc(() async => left(Failure.networkOffline()));
    addTearDown(bloc.close);

    bloc.add(GetMyArticleEditionsEvent(userId: 'u1'));
    final state = await bloc.stream.firstWhere(
      (state) => state is GetBlogsByUserFailure,
    );

    expect((state as GetBlogsByUserFailure).failure.kind, FailureKind.network);
  });
}
