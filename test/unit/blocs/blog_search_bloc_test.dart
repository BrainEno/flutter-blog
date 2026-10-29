import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class _FakeSearchBlogs implements SearchBlogs {
  final Future<Either<Failure, List<Blog>>> Function(String query) _handler;

  _FakeSearchBlogs(this._handler);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);

  @override
  Future<Either<Failure, List<Blog>>> call(SearchBlogsParams params) =>
      _handler(params.query);
}

Blog _blog(String id) => Blog(
  id: id,
  posterId: 'poster',
  title: 'title $id',
  content: 'content',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime(2024),
);

void main() {
  test('whitespace-only query resets to idle without searching', () async {
    var searches = 0;
    final bloc = BlogSearchBloc(
      searchBlogs: _FakeSearchBlogs((query) async {
        searches++;
        return Right([_blog('a')]);
      }),
    );
    final states = <BlogSearchState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const SearchBlogsEvent(query: '   '));
    await bloc.close();
    sub.cancel();

    expect(searches, 0);
    expect(states.last, isA<BlogSearchInitial>());
  });

  test('query is trimmed before searching', () async {
    String? received;
    final bloc = BlogSearchBloc(
      searchBlogs: _FakeSearchBlogs((query) async {
        received = query;
        return const Right([]);
      }),
    );
    bloc.add(const SearchBlogsEvent(query: '  flutter  '));
    await bloc.close();

    expect(received, 'flutter');
  });

  test('only the latest response is emitted when searches overlap', () async {
    var calls = 0;
    final slow = Completer<Either<Failure, List<Blog>>>();
    final bloc = BlogSearchBloc(
      searchBlogs: _FakeSearchBlogs((query) {
        calls++;
        if (calls == 1) return slow.future;
        return Future.value(Right([_blog('new')]));
      }),
    );
    final states = <BlogSearchState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const SearchBlogsEvent(query: 'old'));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const SearchBlogsEvent(query: 'new'));
    await Future<void>.delayed(Duration.zero);
    slow.complete(Right([_blog('stale')]));
    await Future<void>.delayed(Duration.zero);
    await bloc.close();
    sub.cancel();

    final successes = states.whereType<BlogSearchSuccess>().toList();
    expect(successes, hasLength(1));
    expect(successes.single.blogs.map((b) => b.id), ['new']);
  });

  test('clearing discards an in-flight response', () async {
    final slow = Completer<Either<Failure, List<Blog>>>();
    final bloc = BlogSearchBloc(
      searchBlogs: _FakeSearchBlogs((query) => slow.future),
    );
    final states = <BlogSearchState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const SearchBlogsEvent(query: 'something'));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const SearchBlogsCleared());
    await Future<void>.delayed(Duration.zero);
    slow.complete(Right([_blog('late')]));
    await Future<void>.delayed(Duration.zero);
    await bloc.close();
    sub.cancel();

    expect(states.whereType<BlogSearchSuccess>(), isEmpty);
    expect(states.last, isA<BlogSearchInitial>());
  });

  test('failure is surfaced with its message', () async {
    final bloc = BlogSearchBloc(
      searchBlogs: _FakeSearchBlogs((query) async => Left(Failure('离线'))),
    );
    final states = <BlogSearchState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const SearchBlogsEvent(query: 'x'));
    await bloc.close();
    sub.cancel();

    expect(states.last, isA<BlogSearchFailure>());
    expect((states.last as BlogSearchFailure).error, '离线');
  });
}
