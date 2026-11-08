import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/author_articles_paging.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_author_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

Blog _blog(String id) => Blog(
  id: id,
  posterId: 'author',
  title: 'title $id',
  content: 'content',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2024),
);

/// Answers one page per call, recording what it was asked for.
class _Pages implements GetAuthorArticles {
  _Pages({this.pageSize = kAuthorPageSize, this.failure, this.gate});

  /// How many rows each page holds; the bloc infers "has more" from this.
  final int pageSize;

  /// When set, every call after the first answers this instead.
  final Failure? failure;

  /// Holds back the *second* call so a test can decide what happens while it
  /// is still in flight.
  final Completer<void>? gate;

  final List<GetAuthorArticlesParams> calls = [];
  int _served = 0;

  @override
  Future<Either<Failure, List<Blog>>> call(
    GetAuthorArticlesParams params,
  ) async {
    calls.add(params);
    if (_served > 0) {
      final failure = this.failure;
      if (failure != null) return left(failure);
      final gate = this.gate;
      if (gate != null) await gate.future;
    }
    final rows = [
      for (var i = 0; i < pageSize; i++)
        _blog('a${params.offset + i}-${params.kind.name}'),
    ];
    _served++;
    return right(rows);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoArticles implements GetMyArticles {
  @override
  Future<Either<Failure, List<Blog>>> call(GetMyArticlesParams params) async =>
      right(const <Blog>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoEditions implements GetMyArticleEditions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BlogByBloc _bloc(_Pages pages) => BlogByBloc(
  getAuthorArticles: pages,
  getMyArticles: _NoArticles(),
  getMyArticleEditions: _NoEditions(),
);

Future<GetBlogsByUserSuccess> _firstPage(
  BlogByBloc bloc,
  String userId, {
  BlogFeedKind kind = BlogFeedKind.latest,
}) async {
  bloc.add(GetBlogByPosterEvent(userId: userId, kind: kind));
  final state = await bloc.stream.firstWhere(
    (state) => state is GetBlogsByUserSuccess && state.kind == kind,
  );
  return state as GetBlogsByUserSuccess;
}

/// Subscribes before the event is added: the bound is decided locally, so the
/// state can land in the same turn as the request.
Future<GetBlogsByUserSuccess> _depthLimitedBy(
  BlogByBloc bloc,
  BlogByEvent event,
) {
  final found = bloc.stream.firstWhere(
    (state) => state is GetBlogsByUserSuccess && state.depthLimited,
  );
  bloc.add(event);
  return found.then((state) => state as GetBlogsByUserSuccess);
}

void main() {
  test('the first page asks for the newest order at offset zero', () async {
    final pages = _Pages();
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    final state = await _firstPage(bloc, 'author');

    expect(pages.calls.single.kind, BlogFeedKind.latest);
    expect(pages.calls.single.offset, 0);
    expect(state.kind, BlogFeedKind.latest);
    // A full page is the route's only "maybe more" signal.
    expect(state.hasMore, isTrue);
  });

  test('a short first page ends the list', () async {
    final pages = _Pages(pageSize: 3);
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    final state = await _firstPage(bloc, 'author');

    expect(state.hasMore, isFalse);
  });

  test('load more continues at the number of rows already read', () async {
    final pages = _Pages();
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    await _firstPage(bloc, 'author');
    bloc.add(BlogByMoreRequested());
    final more = await bloc.stream.firstWhere(
      (state) => state is GetBlogsByUserSuccess && state.blogs.length > 20,
    );

    expect(pages.calls.map((call) => call.offset), [0, kAuthorPageSize]);
    expect((more as GetBlogsByUserSuccess).blogs.length, 40);
  });

  test('the most-saved order stops at the bound without asking', () async {
    final pages = _Pages(pageSize: kAuthorPopularMaxOffset + kAuthorPageSize);
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    // One page already past the bound: the next request could only be refused.
    final state = await _firstPage(bloc, 'author', kind: BlogFeedKind.popular);
    expect(state.blogs.length, greaterThan(kAuthorPopularMaxOffset));
    final stopped = await _depthLimitedBy(bloc, BlogByMoreRequested());

    // Nothing was sent: the client knows the bound the server enforces.
    expect(pages.calls, hasLength(1));
    expect(stopped.hasMore, isFalse);
  });

  test('a refused deep page is the bound, not a retryable error', () async {
    final pages = _Pages(
      failure: const Failure(
        'offset is limited',
        kind: FailureKind.validation,
        code: 'server.BAD_USER_INPUT',
      ),
    );
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    await _firstPage(bloc, 'author', kind: BlogFeedKind.popular);
    final stopped = await _depthLimitedBy(bloc, BlogByMoreRequested());

    expect(stopped.blogs, hasLength(20));
    expect(stopped.loadMoreFailure, isNull);
  });

  test('an ordinary failure keeps the rows and offers a retry', () async {
    final pages = _Pages(
      failure: const Failure('offline', kind: FailureKind.network),
    );
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    await _firstPage(bloc, 'author');
    bloc.add(BlogByMoreRequested());
    final failed = await bloc.stream.firstWhere(
      (state) =>
          state is GetBlogsByUserSuccess && state.loadMoreFailure != null,
    );

    expect((failed as GetBlogsByUserSuccess).blogs, hasLength(20));
    expect(failed.depthLimited, isFalse);
  });

  test('switching order asks again with the other sort', () async {
    final pages = _Pages();
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    await _firstPage(bloc, 'author');
    bloc.add(
      GetBlogByPosterEvent(userId: 'author', kind: BlogFeedKind.popular),
    );
    final popular = await bloc.stream.firstWhere(
      (state) =>
          state is GetBlogsByUserSuccess && state.kind == BlogFeedKind.popular,
    );

    expect(pages.calls.last.kind, BlogFeedKind.popular);
    expect((popular as GetBlogsByUserSuccess).blogs, hasLength(20));
  });

  test('a page that arrives after a switch is dropped', () async {
    final gate = Completer<void>();
    final pages = _Pages(gate: gate);
    final bloc = _bloc(pages);
    addTearDown(bloc.close);

    await _firstPage(bloc, 'author');
    // Ask for more in the newest order, then switch to the most-saved one
    // before that page lands. Its offsets describe the list being left behind.
    bloc.add(BlogByMoreRequested());
    await Future<void>.delayed(Duration.zero);
    bloc.add(
      GetBlogByPosterEvent(userId: 'author', kind: BlogFeedKind.popular),
    );
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    final state = bloc.state as GetBlogsByUserSuccess;
    expect(state.kind, BlogFeedKind.popular);
    expect(pages.calls.map((call) => call.kind), [
      BlogFeedKind.latest,
      BlogFeedKind.latest,
      BlogFeedKind.popular,
    ]);
    // Exactly one page of the new order - the stale page was not appended.
    expect(state.blogs, hasLength(kAuthorPageSize));
  });
}
