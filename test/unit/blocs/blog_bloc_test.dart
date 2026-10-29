import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class _FakeGetAllBlogs implements GetAllBlogs {
  final Future<Either<Failure, List<Blog>>> Function(int page) _handler;

  _FakeGetAllBlogs(this._handler);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Either<Failure, List<Blog>>> call(GetAllBlogsParams params) =>
      _handler(params.page);
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
  group('BlogBloc first page', () {
    test('emits BlogLoaded with hasReachedMax when fewer than a page '
        'comes back', () async {
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs(
          (page) async => Right([_blog('a'), _blog('b')]),
        ),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await bloc.close();
      sub.cancel();

      expect(states.length, 2, reason: 'loading then loaded');
      expect(states[0], isA<BlogFirstPageLoading>());
      final loaded = states[1] as BlogLoaded;
      expect(loaded.blogs.map((b) => b.id), ['a', 'b']);
      expect(loaded.page, 1);
      expect(loaded.hasReachedMax, isTrue);
    });

    test('reports failure instead of pretending to load forever', () async {
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs((page) async => Left(Failure('网络错误'))),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await bloc.close();
      sub.cancel();

      expect(states[1], isA<BlogListFailure>());
      expect((states[1] as BlogListFailure).error, '网络错误');
    });

    test('a stale first-page response never overwrites a newer one', () async {
      // First request stays pending; the second one resolves immediately
      // with different data.
      var calls = 0;
      final slow = Completer<Either<Failure, List<Blog>>>();
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs((page) {
          calls++;
          if (calls == 1) return slow.future;
          return Future.value(Right([_blog('new')]));
        }),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      // Resolve the STALE request with data the UI must never see.
      slow.complete(Right([_blog('stale')]));
      await Future<void>.delayed(Duration.zero);
      await bloc.close();
      sub.cancel();

      final loaded = states.whereType<BlogLoaded>().toList();
      expect(loaded, hasLength(1));
      expect(loaded.single.blogs.map((b) => b.id), [
        'new',
      ], reason: 'stale response must be discarded');
    });
  });

  group('BlogBloc load more', () {
    test('appends the next page and deduplicates by id', () async {
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs((page) async {
          if (page == 1) {
            return Right(List.generate(10, (i) => _blog('a$i')));
          }
          // Page shift: a0 moved down into page 2 between the requests.
          return Right([_blog('a0'), ...List.generate(9, (i) => _blog('b$i'))]);
        }),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const BlogLoadMore());
      await bloc.close();
      sub.cancel();

      final loaded = states.whereType<BlogLoaded>().last;
      expect(loaded.blogs.map((b) => b.id), [
        ...List.generate(10, (i) => 'a$i'),
        ...List.generate(9, (i) => 'b$i'),
      ]);
      expect(loaded.page, 2);
      // The server still returned a full page (10 rows, one duplicated), so
      // the end is not reached even though only 9 were new.
      expect(loaded.hasReachedMax, isFalse);
    });

    test('ignores load-more while another one is running', () async {
      var loadMoreCalls = 0;
      final gate = Completer<void>();
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs((page) async {
          if (page == 1) return Right(List.generate(10, (i) => _blog('a$i')));
          loadMoreCalls++;
          await gate.future;
          return Right(List.generate(10, (i) => _blog('b$i')));
        }),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      // Double-fire the scroll listener, like a janky scroll frame does.
      bloc.add(const BlogLoadMore());
      bloc.add(const BlogLoadMore());
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await bloc.close();
      sub.cancel();

      expect(loadMoreCalls, 1, reason: 'second request must not be sent');
      final loaded = states.whereType<BlogLoaded>().last;
      expect(loaded.page, 2);
    });

    test('a refresh that starts mid load-more supersedes the append', () async {
      final gate = Completer<void>();
      var calls = 0;
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs((page) {
          calls++;
          if (calls == 1) {
            return Future.value(
              Right(List.generate(10, (i) => _blog('first$i'))),
            );
          }
          if (calls == 2) {
            return gate.future.then(
              (_) => Right(List.generate(10, (i) => _blog('stale-more$i'))),
            );
          }
          return Future.value(
            Right(List.generate(3, (i) => _blog('refresh$i'))),
          );
        }),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const BlogLoadMore());
      await Future<void>.delayed(Duration.zero);
      // Refresh wins the race while the load-more request is still pending.
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await bloc.close();
      sub.cancel();

      final loaded = states.whereType<BlogLoaded>().last;
      expect(loaded.blogs.map((b) => b.id), [
        'refresh0',
        'refresh1',
        'refresh2',
      ], reason: 'the stale append must be discarded');
      expect(loaded.page, 1);
      expect(loaded.hasReachedMax, isTrue);
    });

    test('empty next page marks the end', () async {
      final bloc = BlogBloc(
        getAllBlogs: _FakeGetAllBlogs((page) async {
          if (page == 1) return Right(List.generate(10, (i) => _blog('a$i')));
          return const Right([]);
        }),
      );
      final states = <BlogState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(const BlogFetchFirstPage());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const BlogLoadMore());
      await bloc.close();
      sub.cancel();

      final loaded = states.whereType<BlogLoaded>().last;
      expect(loaded.hasReachedMax, isTrue);
      expect(loaded.isLoadingMore, isFalse);
      expect(loaded.blogs, hasLength(10));
    });

    test(
      'load-more failure keeps the previous list and clears the flag',
      () async {
        final bloc = BlogBloc(
          getAllBlogs: _FakeGetAllBlogs((page) async {
            if (page == 1) return Right(List.generate(10, (i) => _blog('a$i')));
            return Left(Failure('网络中断'));
          }),
        );
        final states = <BlogState>[];
        final sub = bloc.stream.listen(states.add);
        bloc.add(const BlogFetchFirstPage());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const BlogLoadMore());
        await bloc.close();
        sub.cancel();

        final failure = states.whereType<BlogListFailure>().single;
        final previous = failure.previousState as BlogLoaded;
        expect(previous.blogs, hasLength(10));
        expect(previous.isLoadingMore, isFalse);
      },
    );
  });
}
