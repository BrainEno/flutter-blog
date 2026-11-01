import 'dart:convert';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _Local extends Mock implements BlogLocalDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

class _Row {
  const _Row(this.id, this.microseconds);
  final int id;
  final int microseconds;

  Map<String, dynamic> toJson() {
    final time = DateTime.fromMillisecondsSinceEpoch(
      microseconds ~/ 1000,
      isUtc: true,
    ).toIso8601String();
    return {
      'id': _uuid(id),
      'slug': 'article-$id',
      'title': 'Title $id',
      'authorId': 'author',
      'contentBlocksVersion': 0,
      'contentBlocks': [
        {'id': 'p1', 'type': 'paragraph', 'text': 'body'},
      ],
      'publishedAt': time,
      'updatedAt': time,
    };
  }
}

Future<BlogLoaded> _fetch(BlogBloc bloc, BlogEvent event, int page) async {
  final result = bloc.stream.firstWhere(
    (state) =>
        state is BlogLoaded && state.page == page && !state.isLoadingMore,
  );
  bloc.add(event);
  return await result as BlogLoaded;
}

void main() {
  setUpAll(() => registerFallbackValue(<BlogModel>[]));

  test(
    'real client/repository/bloc walks microseconds while new work is published',
    () async {
      final base = DateTime.utc(2026, 11).millisecondsSinceEpoch;
      final original = [
        for (var i = 24; i >= 0; i--) _Row(500 - i, (base + 123) * 1000 + i),
        for (var i = 9; i >= 0; i--) _Row(900 - i, (base + 122) * 1000 + i),
      ];
      final serverRows = [...original];
      final requests = <Uri>[];
      final httpClient = MockClient((request) async {
        requests.add(request.url);
        final query = request.url.queryParameters;
        final limit = int.parse(query['limit']!);
        Iterable<_Row> matching = serverRows;
        if (query['cursor'] case final String encoded) {
          expect(query.containsKey('offset'), isFalse);
          final decoded = utf8.decode(
            base64Url.decode(base64Url.normalize(encoded)),
          );
          final pieces = decoded.split('|');
          expect(pieces.last, '00000000-0000-0000-0000-000000000000');
          final upperMicros =
              DateTime.parse(pieces.first).millisecondsSinceEpoch * 1000;
          matching = matching.where((row) => row.microseconds < upperMicros);
        } else {
          matching = matching.skip(int.parse(query['offset'] ?? '0'));
        }
        return http.Response(
          jsonEncode({
            'data': matching.take(limit).map((row) => row.toJson()).toList(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(httpClient.close);
      final remote = BlogRemoteDataSourceImpl(
        NowaveApiClient(
          baseUrl: Uri.parse('https://example.invalid'),
          httpClient: httpClient,
        ),
      );
      final local = _Local();
      final connection = _Connection();
      when(() => connection.isConnected).thenAnswer((_) async => true);
      when(
        () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
      ).thenAnswer((_) async {});
      final bloc = BlogBloc(
        getAllBlogs: GetAllBlogs(BlogRepositoryImpl(remote, local, connection)),
      );
      addTearDown(bloc.close);

      final first = await _fetch(bloc, const BlogFetchFirstPage(), 1);
      expect(first.blogs, hasLength(10));
      expect(first.nextCursor, isNotNull);
      serverRows.insert(0, _Row(1, (base + 124) * 1000 + 1));
      await _fetch(bloc, const BlogLoadMore(), 2);
      await _fetch(bloc, const BlogLoadMore(), 3);
      final last = await _fetch(bloc, const BlogLoadMore(), 4);

      expect(last.hasReachedMax, isTrue);
      expect(last.blogs.map((blog) => blog.id), [
        for (final row in original) 'article-${row.id}',
      ]);
      expect(last.blogs.map((blog) => blog.id).toSet(), hasLength(35));
      expect(requests, hasLength(4));
      expect(requests.first.queryParameters['offset'], '0');
      expect(
        requests
            .skip(1)
            .every((uri) => uri.queryParameters.containsKey('cursor')),
        isTrue,
      );
      verify(
        () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
      ).called(4);
    },
  );
}
