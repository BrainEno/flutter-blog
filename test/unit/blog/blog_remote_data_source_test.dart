import 'dart:async';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNowaveApiClient extends Mock implements NowaveApiClient {}

const _kSlug = 'my-slug';

BlogModel _blog() => BlogModel(
  id: _kSlug,
  articleId: 'server-uuid-1',
  title: '标题',
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const ['诗歌'],
  updatedAt: DateTime.utc(2025),
);

/// A full article envelope as `GET /articles/:slug` returns it.
Map<String, dynamic> _articleMap({bool likedByViewer = false}) {
  return <String, dynamic>{
    'id': 'server-uuid-1',
    'slug': _kSlug,
    'title': '标题',
    'authorId': 'u1',
    'contentBlocks': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'b1', 'type': 'paragraph', 'text': '正文'},
    ],
    'tags': <Map<String, dynamic>>[
      <String, dynamic>{'id': 't1', 'name': '诗歌', 'slug': 'shi-ge'},
    ],
    'author': <String, dynamic>{'displayName': '作者'},
    'updatedAt': '2025-01-01T00:00:00.000Z',
    'likedByViewer': likedByViewer,
  };
}

void main() {
  late MockNowaveApiClient client;
  late BlogRemoteDataSourceImpl dataSource;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = MockNowaveApiClient();
    dataSource = BlogRemoteDataSourceImpl(client);
  });

  group('toggleLikeBlog', () {
    test('reads the current state and writes the opposite', () async {
      when(
        () => client.getJson(
          '/articles/$_kSlug/like',
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => _articleMap(likedByViewer: false));
      when(
        () => client.putJson('/articles/$_kSlug/like', {'liked': true}),
      ).thenAnswer((_) async => _articleMap(likedByViewer: true));

      final liked = await dataSource.toggleLikeBlog('u1', _kSlug);

      expect(liked, isTrue);
      verify(
        () => client.getJson(
          '/articles/$_kSlug/like',
          query: any(named: 'query'),
        ),
      ).called(1);
      verify(() => client.putJson('/articles/$_kSlug/like', {'liked': true}))
          .called(1);
    });

    test(
      'concurrent toggles on the same article share one exchange',
      () async {
        // Slow the read down so both callers would interleave without
        // per-article serialization.
        final release = Completer<void>();
        var reads = 0;
        when(
          () => client.getJson(
            '/articles/$_kSlug/like',
            query: any(named: 'query'),
          ),
        ).thenAnswer((_) async {
          reads++;
          await release.future;
          return _articleMap(likedByViewer: false);
        });
        when(
          () => client.putJson('/articles/$_kSlug/like', {'liked': true}),
        ).thenAnswer((_) async => _articleMap(likedByViewer: true));

        final first = dataSource.toggleLikeBlog('u1', _kSlug);
        final second = dataSource.toggleLikeBlog('u1', _kSlug);
        // Let both calls reach the in-flight map before releasing.
        await Future<void>.delayed(Duration.zero);
        release.complete();

        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(reads, 1);
        verify(
          () => client.putJson('/articles/$_kSlug/like', {'liked': true}),
        ).called(1);
      },
    );

    test('a later toggle runs its own exchange', () async {
      when(
        () => client.getJson(
          '/articles/$_kSlug/like',
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => _articleMap(likedByViewer: true));
      when(
        () => client.putJson('/articles/$_kSlug/like', {'liked': false}),
      ).thenAnswer((_) async => _articleMap(likedByViewer: false));

      await dataSource.toggleLikeBlog('u1', _kSlug);
      final liked = await dataSource.toggleLikeBlog('u1', _kSlug);

      expect(liked, isFalse);
      verify(
        () => client.getJson(
          '/articles/$_kSlug/like',
          query: any(named: 'query'),
        ),
      ).called(2);
    });
  });

  group('tag resolution', () {
    test('concurrent publishes resolve the same tag once', () async {
      var tagPosts = 0;
      when(() => client.postJson('/tags', {'name': '诗歌'})).thenAnswer(
        (_) async {
          tagPosts++;
          // Slow the first resolution down so a second caller would fire
          // its own request without in-flight sharing.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return <String, dynamic>{'id': 't1', 'name': '诗歌', 'slug': 's'};
        },
      );
      when(() => client.postJson('/articles', any())).thenAnswer((_) async {
        return _articleMap();
      });

      final blog = _blog();
      await Future.wait([
        dataSource.uploadBlog(blog),
        dataSource.uploadBlog(blog),
      ]);

      expect(tagPosts, 1);
    });
  });
}
