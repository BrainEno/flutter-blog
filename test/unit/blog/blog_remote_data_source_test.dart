import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
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
    'summary': '作者的摘要',
    'authorId': 'u1',
    'contentBlocksVersion': 0,
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

  group('online feeds', () {
    test(
      'featured uses the editorial endpoint and keeps server order',
      () async {
        when(
          () => client.getJson('/featured', query: any(named: 'query')),
        ).thenAnswer(
          (_) async => [
            {..._articleMap(), 'slug': 'editor-first'},
            {..._articleMap(), 'slug': 'editor-second'},
          ],
        );

        final blogs = await dataSource.getOnlineFeed(
          page: 2,
          kind: BlogFeedKind.featured,
        );

        expect(blogs.map((blog) => blog.id), ['editor-first', 'editor-second']);
        verify(
          () => client.getJson(
            '/featured',
            query: {'limit': '10', 'offset': '10', 'locale': 'zh-CN'},
          ),
        ).called(1);
        verifyNever(
          () => client.getJson('/articles', query: any(named: 'query')),
        );
      },
    );

    test('popular sends the documented ranking and page offset', () async {
      when(
        () => client.getJson('/articles', query: any(named: 'query')),
      ).thenAnswer((_) async => [_articleMap()]);

      final blogs = await dataSource.getOnlineFeed(
        page: 3,
        kind: BlogFeedKind.popular,
      );

      expect(blogs.single.id, _kSlug);
      verify(
        () => client.getJson(
          '/articles',
          query: {
            'limit': '10',
            'offset': '20',
            'locale': 'zh-CN',
            'sort': 'popular',
          },
        ),
      ).called(1);
      verifyNever(
        () => client.getJsonForViewer(
          any(),
          expectedUserId: any(named: 'expectedUserId'),
          query: any(named: 'query'),
        ),
      );
    });

    test(
      'following uses a viewer-fenced request without sending the ID',
      () async {
        when(
          () => client.getJsonForViewer(
            '/me/feed',
            expectedUserId: 'viewer-A',
            query: any(named: 'query'),
          ),
        ).thenAnswer((_) async => [_articleMap()]);

        final blogs = await dataSource.getOnlineFeed(
          page: 2,
          kind: BlogFeedKind.following,
          expectedViewerId: 'viewer-A',
        );

        expect(blogs.single.id, _kSlug);
        verify(
          () => client.getJsonForViewer(
            '/me/feed',
            expectedUserId: 'viewer-A',
            query: {'limit': '10', 'offset': '10', 'locale': 'zh-CN'},
          ),
        ).called(1);
        verifyNever(() => client.getJson(any(), query: any(named: 'query')));
      },
    );

    test(
      'following transport errors do not restart under another session',
      () async {
        when(
          () => client.getJsonForViewer(
            '/me/feed',
            expectedUserId: 'viewer-A',
            query: any(named: 'query'),
          ),
        ).thenThrow(const SocketException('offline'));

        await expectLater(
          dataSource.getOnlineFeed(
            page: 1,
            kind: BlogFeedKind.following,
            expectedViewerId: 'viewer-A',
          ),
          throwsA(isA<ServerException>()),
        );
        verify(
          () => client.getJsonForViewer(
            '/me/feed',
            expectedUserId: 'viewer-A',
            query: any(named: 'query'),
          ),
        ).called(1);
      },
    );
  });

  test('direct edit also rejects unknown or unsupported structure', () async {
    await expectLater(
      dataSource.editBlog(_blog()),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'article.structuredEditUnsupported',
        ),
      ),
    );
    verifyNever(() => client.postJson(any(), any()));
    verifyNever(() => client.putJson(any(), any()));
  });

  test('direct edit sends the fresh server summary', () async {
    final original = BlogModel.fromNowaveArticle({
      ..._articleMap(),
      'tags': <Map<String, dynamic>>[],
    });
    when(
      () => client.putJson('/articles/server-uuid-1', any()),
    ).thenAnswer((_) async => _articleMap());

    await dataSource.editBlog(original.copyWith(title: '新标题', content: '新正文'));

    final body =
        verify(
              () => client.putJson('/articles/server-uuid-1', captureAny()),
            ).captured.single
            as Map<String, dynamic>;
    expect(body['summary'], '作者的摘要');
    expect(body['contentBlocksVersion'], 0);
  });

  test('direct edit rejects an unknown server summary', () async {
    final document = _articleMap()..remove('summary');
    final original = BlogModel.fromNowaveArticle(document);
    expect(original.plainEditorCompatible, isTrue);

    await expectLater(
      dataSource.editBlog(original),
      throwsA(
        isA<ServerException>().having(
          (error) => error.code,
          'code',
          'article.structuredEditUnsupported',
        ),
      ),
    );
    verifyNever(() => client.postJson(any(), any()));
    verifyNever(() => client.putJson(any(), any()));
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
      verify(
        () => client.putJson('/articles/$_kSlug/like', {'liked': true}),
      ).called(1);
    });

    test('concurrent toggles on the same article share one exchange', () async {
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
    });

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

  group('categories and tags on the write path', () {
    setUp(() {
      when(
        () => client.postJson(
          '/articles',
          any(),
          extraHeaders: any(named: 'extraHeaders'),
        ),
      ).thenAnswer((_) async => _articleMap());
      when(() => client.postJson('/tags', any())).thenAnswer(
        (_) async => <String, dynamic>{'id': 't1', 'name': '诗歌', 'slug': 's'},
      );
    });

    Map<String, dynamic> capturedCreate() =>
        verify(
              () => client.postJson(
                '/articles',
                captureAny(),
                extraHeaders: any(named: 'extraHeaders'),
              ),
            ).captured.single
            as Map<String, dynamic>;

    test('an untouched picker leaves categoryIds out entirely', () async {
      await dataSource.uploadBlog(_blog());

      // Omitted, not empty: the server keeps whatever categories the article
      // already has, because the app is not allowed to invent or drop them.
      expect(capturedCreate().containsKey('categoryIds'), isFalse);
    });

    test('a chosen category is sent as one id', () async {
      await dataSource.uploadBlog(_blog(), categoryIds: const ['cat-1']);

      expect(capturedCreate()['categoryIds'], ['cat-1']);
    });

    test('clearing the picker sends an empty list', () async {
      await dataSource.uploadBlog(_blog(), categoryIds: const []);

      expect(capturedCreate()['categoryIds'], isEmpty);
    });

    test('tags are always sent, so removing the last one sticks', () async {
      await dataSource.uploadBlog(
        BlogModel(
          id: '',
          title: '标题',
          content: '正文',
          posterId: 'u1',
          imageUrl: '',
          tags: const [],
          updatedAt: DateTime.utc(2025),
        ),
      );

      expect(capturedCreate()['tagIds'], isEmpty);
    });

    test('an edit follows the same three rules', () async {
      final original = BlogModel.fromNowaveArticle(_articleMap());
      when(
        () => client.putJson('/articles/server-uuid-1', any()),
      ).thenAnswer((_) async => _articleMap());

      await dataSource.editBlog(original, categoryIds: const ['cat-2']);

      final body =
          verify(
                () => client.putJson('/articles/server-uuid-1', captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['categoryIds'], ['cat-2']);
      expect(body['tagIds'], ['t1']);
    });

    test('an untouched edit keeps the article categories', () async {
      final original = BlogModel.fromNowaveArticle(_articleMap());
      when(
        () => client.putJson('/articles/server-uuid-1', any()),
      ).thenAnswer((_) async => _articleMap());

      await dataSource.editBlog(original);

      final body =
          verify(
                () => client.putJson('/articles/server-uuid-1', captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body.containsKey('categoryIds'), isFalse);
    });
  });

  group('tag resolution', () {
    test('concurrent publishes resolve the same tag once', () async {
      var tagPosts = 0;
      when(() => client.postJson('/tags', {'name': '诗歌'})).thenAnswer((
        _,
      ) async {
        tagPosts++;
        // Slow the first resolution down so a second caller would fire
        // its own request without in-flight sharing.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return <String, dynamic>{'id': 't1', 'name': '诗歌', 'slug': 's'};
      });
      when(
        () => client.postJson(
          '/articles',
          any(),
          extraHeaders: any(named: 'extraHeaders'),
        ),
      ).thenAnswer((_) async => _articleMap());

      final blog = _blog();
      await Future.wait([
        dataSource.uploadBlog(blog),
        dataSource.uploadBlog(blog),
      ]);

      expect(tagPosts, 1);
    });
  });

  group('deleteArticle', () {
    test('DELETEs the article by its server UUID', () async {
      when(() => client.deleteJson('/articles/server-uuid-1')).thenAnswer(
        (_) async => <String, dynamic>{
          'id': 'server-uuid-1',
          'deletedAt': '2026-10-30T00:00:00.000Z',
        },
      );

      expect(await dataSource.deleteArticle('server-uuid-1'), isTrue);
      verify(() => client.deleteJson('/articles/server-uuid-1')).called(1);
    });

    test('an empty article id is rejected without a request', () async {
      await expectLater(
        () => dataSource.deleteArticle(''),
        throwsA(isA<ServerException>()),
      );
      verifyNever(() => client.deleteJson(any()));
    });

    test('a 404 tombstone maps to a ServerException', () async {
      when(() => client.deleteJson('/articles/server-uuid-1')).thenThrow(
        const NowaveApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'The article was not found.',
        ),
      );

      await expectLater(
        () => dataSource.deleteArticle('server-uuid-1'),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('getDeletedBlogs', () {
    Map<String, dynamic> tombstone({String? purgesAt}) => <String, dynamic>{
      'id': 'server-uuid-1',
      'slug': 'gone-deleted-abcdef12',
      'title': '被删的文章',
      'contentBlocks': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'b0',
          'type': 'image',
          'src': 'https://api.example.invalid/cover.webp',
        },
        <String, dynamic>{'id': 'b1', 'type': 'paragraph', 'text': '正文'},
      ],
      'deletedAt': '2026-10-01T00:00:00.000Z',
      if (purgesAt != null) 'purgesAt': purgesAt,
    };

    test('lists tombstones with the server-computed purge deadline', () async {
      when(
        () =>
            client.getJson('/me/articles/deleted', query: any(named: 'query')),
      ).thenAnswer(
        (_) async => [tombstone(purgesAt: '2026-10-31T00:00:00.000Z')],
      );

      final blogs = await dataSource.getDeletedBlogs();

      expect(blogs, hasLength(1));
      final entry = blogs.single;
      expect(entry.articleId, 'server-uuid-1');
      expect(entry.title, '被删的文章');
      expect(entry.imageUrl, 'https://api.example.invalid/cover.webp');
      expect(entry.deletedAt, DateTime.parse('2026-10-01T00:00:00.000Z'));
      expect(entry.purgesAt, DateTime.parse('2026-10-31T00:00:00.000Z'));
    });

    test('a tombstone without purgesAt carries no expiry promise', () async {
      when(
        () =>
            client.getJson('/me/articles/deleted', query: any(named: 'query')),
      ).thenAnswer((_) async => [tombstone()]);

      expect((await dataSource.getDeletedBlogs()).single.purgesAt, isNull);
    });

    test('a non-list payload is a server failure', () async {
      when(
        () =>
            client.getJson('/me/articles/deleted', query: any(named: 'query')),
      ).thenAnswer((_) async => <String, dynamic>{'unexpected': true});

      await expectLater(
        () => dataSource.getDeletedBlogs(),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('getMyArticles', () {
    test('reads the account-scoped list and marks drafts', () async {
      when(
        () => client.getJsonForViewer(
          '/me/articles',
          expectedUserId: 'u1',
          query: any(named: 'query'),
        ),
      ).thenAnswer(
        (_) async => [
          {..._articleMap(), 'slug': 'a-draft', 'status': 'draft'},
          {..._articleMap(), 'slug': 'published', 'status': 'published'},
        ],
      );

      final blogs = await dataSource.getMyArticles(userId: 'u1');

      expect(blogs.map((blog) => blog.id), ['a-draft', 'published']);
      expect(blogs.map((blog) => blog.isDraft), [true, false]);
      verify(
        () => client.getJsonForViewer(
          '/me/articles',
          expectedUserId: 'u1',
          query: {'limit': '100', 'locale': 'zh-CN'},
        ),
      ).called(1);
    });

    test(
      'a deployment without the endpoint falls back to the public list',
      () async {
        when(
          () => client.getJsonForViewer(
            '/me/articles',
            expectedUserId: any(named: 'expectedUserId'),
            query: any(named: 'query'),
          ),
        ).thenThrow(
          const NowaveApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'Not found.',
          ),
        );
        when(
          () => client.getJson(
            '/authors/u1/articles',
            query: any(named: 'query'),
          ),
        ).thenAnswer((_) async => [_articleMap()]);

        final blogs = await dataSource.getMyArticles(userId: 'u1');

        expect(blogs.single.id, _kSlug);
        expect(blogs.single.isDraft, isFalse);
      },
    );

    test(
      'other failures still surface instead of faking an empty list',
      () async {
        when(
          () => client.getJsonForViewer(
            '/me/articles',
            expectedUserId: any(named: 'expectedUserId'),
            query: any(named: 'query'),
          ),
        ).thenThrow(
          const NowaveApiException(
            statusCode: 401,
            code: 'UNAUTHENTICATED',
            message: 'Sign in required.',
          ),
        );

        await expectLater(
          () => dataSource.getMyArticles(userId: 'u1'),
          throwsA(isA<ServerException>()),
        );
        verifyNever(
          () => client.getJson(
            '/authors/u1/articles',
            query: any(named: 'query'),
          ),
        );
      },
    );
  });

  group('restoreArticle', () {
    test('POSTs the restore with the locale and parses the draft', () async {
      when(
        () => client.postJson(
          '/articles/server-uuid-1/restore',
          null,
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => _articleMap());

      final blog = await dataSource.restoreArticle('server-uuid-1');

      expect(blog.id, _kSlug);
      expect(blog.articleId, 'server-uuid-1');
      verify(
        () => client.postJson(
          '/articles/server-uuid-1/restore',
          null,
          query: {'locale': 'zh-CN'},
        ),
      ).called(1);
    });

    test('a 404 (not a tombstone) maps to a ServerException', () async {
      when(
        () => client.postJson(
          '/articles/server-uuid-1/restore',
          null,
          query: any(named: 'query'),
        ),
      ).thenThrow(
        const NowaveApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'The article was not found.',
        ),
      );

      await expectLater(
        () => dataSource.restoreArticle('server-uuid-1'),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
