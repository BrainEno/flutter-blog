import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Remote extends Mock implements BlogRemoteDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

BlogModel _blog(String id) => BlogModel(
  id: id,
  title: 'title $id',
  content: 'body $id',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2025),
);

Future<BlogLoaded> _load(BlogBloc bloc, BlogEvent event) async {
  final result = bloc.stream.firstWhere(
    (state) => state is BlogLoaded && !state.isLoadingMore,
  );
  bloc.add(event);
  return (await result) as BlogLoaded;
}

void main() {
  test(
    'real SQLite cache paginates offline and refreshes on reconnection',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final cache = SqliteBlogCache(database);
      final remote = _Remote();
      final connection = _Connection();
      var online = false;
      when(() => connection.isConnected).thenAnswer((_) async => online);
      await cache.uploadLocalBlogs(
        blogs: List.generate(
          23,
          (i) => _blog('item-${i.toString().padLeft(2, '0')}'),
        ),
      );
      final repository = BlogRepositoryImpl(remote, cache, connection);
      final bloc = BlogBloc(getAllBlogs: GetAllBlogs(repository));
      addTearDown(() async {
        await bloc.close();
        await database.close();
      });

      final first = await _load(bloc, const BlogFetchFirstPage());
      expect(first.source, BlogFeedSource.cache);
      expect(first.blogs, hasLength(10));
      expect(first.hasReachedMax, isFalse);

      // Reconnection alone must not switch the underlying pagination source.
      online = true;
      final second = await _load(bloc, const BlogLoadMore());
      expect(second.source, BlogFeedSource.cache);
      expect(second.blogs, hasLength(20));
      final third = await _load(bloc, const BlogLoadMore());
      expect(third.source, BlogFeedSource.cache);
      expect(
        third.blogs.map((blog) => blog.id),
        List.generate(23, (i) => 'item-${i.toString().padLeft(2, '0')}'),
      );
      expect(third.page, 3);
      expect(third.hasReachedMax, isTrue);
      bloc.add(const BlogLoadMore());
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => remote.getAllBlogs(page: any(named: 'page')));

      when(
        () => remote.getAllBlogs(page: 1),
      ).thenAnswer((_) async => [_blog('online')]);
      final refreshed = await _load(bloc, const BlogFetchFirstPage());
      expect(refreshed.source, BlogFeedSource.network);
      expect(refreshed.blogs.map((blog) => blog.id), ['online']);
      expect(refreshed.page, 1);
      verify(() => remote.getAllBlogs(page: 1)).called(1);
    },
  );

  test(
    'losing connectivity during online paging retains the list until refresh',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final cache = SqliteBlogCache(database);
      final remote = _Remote();
      final connection = _Connection();
      var online = true;
      when(() => connection.isConnected).thenAnswer((_) async => online);
      when(() => remote.getAllBlogs(page: 1)).thenAnswer(
        (_) async => List.generate(
          10,
          (i) => _blog('item-${i.toString().padLeft(2, '0')}'),
        ),
      );
      final repository = BlogRepositoryImpl(remote, cache, connection);
      final bloc = BlogBloc(getAllBlogs: GetAllBlogs(repository));
      addTearDown(() async {
        await bloc.close();
        await database.close();
      });

      final first = await _load(bloc, const BlogFetchFirstPage());
      expect(first.source, BlogFeedSource.network);
      expect(first.blogs, hasLength(10));
      online = false;
      final error = bloc.stream.firstWhere((state) => state is BlogListFailure);
      bloc.add(const BlogLoadMore());
      final failed = (await error) as BlogListFailure;
      final previous = failed.previousState as BlogLoaded;
      expect(previous.blogs, hasLength(10));
      expect(previous.source, BlogFeedSource.network);
      expect(previous.isLoadingMore, isFalse);
      verifyNever(() => remote.getAllBlogs(page: 2));

      final cached = await _load(bloc, const BlogFetchFirstPage());
      expect(cached.source, BlogFeedSource.cache);
      expect(cached.blogs, hasLength(10));
      final end = await _load(bloc, const BlogLoadMore());
      expect(end.blogs, hasLength(10));
      expect(end.hasReachedMax, isTrue);
    },
  );
}
