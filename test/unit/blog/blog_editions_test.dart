import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/transport/api_envelope.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNowaveApiClient extends Mock implements NowaveApiClient {}

/// A full article envelope, in the edition the server answered with.
Map<String, dynamic> _articleMap({String locale = 'zh-CN'}) {
  return <String, dynamic>{
    'id': 'server-uuid-1',
    'slug': 'my-slug',
    'title': '标题',
    'summary': '作者的摘要',
    'authorId': 'u1',
    'locale': locale,
    'contentBlocksVersion': 0,
    'contentBlocks': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'b1', 'type': 'paragraph', 'text': '正文'},
    ],
    'tags': <Map<String, dynamic>>[],
    'author': <String, dynamic>{'displayName': '作者'},
    'updatedAt': '2025-01-01T00:00:00.000Z',
  };
}

/// The content language the app is displaying right now.
ContentLocale _contentLocale(ContentLanguage language) {
  final locale = ContentLocale()..update(language);
  return locale;
}

void main() {
  late MockNowaveApiClient client;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = MockNowaveApiClient();
  });

  group('an article knows its edition', () {
    test('the payload locale is kept on the model', () {
      final blog = BlogModel.fromNowaveArticle(_articleMap(locale: 'en'));

      expect(blog.locale, 'en');
    });

    test('a payload without a locale leaves the edition unknown', () {
      final document = _articleMap()..remove('locale');
      final blog = BlogModel.fromNowaveArticle(document);

      expect(blog.locale, isEmpty);
    });
  });

  group('writes name the edition, not the display language', () {
    test('PUT carries the article own locale', () async {
      // The reader switched the interface to English after opening a Chinese
      // edition; saving must still rewrite the Chinese translation.
      final dataSource = BlogRemoteDataSourceImpl(
        client,
        contentLocale: _contentLocale(ContentLanguage.en),
      );
      final original = BlogModel.fromNowaveArticle(_articleMap());
      when(
        () => client.putJson('/articles/server-uuid-1', any()),
      ).thenAnswer((_) async => _articleMap());

      await dataSource.editBlog(original.copyWith(title: '新标题'));

      final body =
          verify(
                () => client.putJson('/articles/server-uuid-1', captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['locale'], 'zh-CN');
    });

    test('an unknown edition falls back to the content language', () async {
      final dataSource = BlogRemoteDataSourceImpl(
        client,
        contentLocale: _contentLocale(ContentLanguage.en),
      );
      final original = BlogModel.fromNowaveArticle(
        _articleMap(),
      ).copyWith(locale: '', title: '新标题');
      when(
        () => client.putJson('/articles/server-uuid-1', any()),
      ).thenAnswer((_) async => _articleMap(locale: 'en'));

      await dataSource.editBlog(original);

      final body =
          verify(
                () => client.putJson('/articles/server-uuid-1', captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['locale'], 'en');
    });

    test('reading an edition asks for that language', () async {
      final dataSource = BlogRemoteDataSourceImpl(
        client,
        contentLocale: _contentLocale(ContentLanguage.en),
      );
      when(
        () => client.getJson(
          '/articles/my-slug',
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => _articleMap(locale: 'zh-TW'));

      final blog = await dataSource.getBlogById('my-slug', locale: 'zh-TW');

      expect(blog.locale, 'zh-TW');
      verify(
        () => client.getJson(
          '/articles/my-slug',
          query: {'locale': 'zh-TW'},
        ),
      ).called(1);
    });

    test('restoring a tombstone names its own language', () async {
      final dataSource = BlogRemoteDataSourceImpl(
        client,
        contentLocale: _contentLocale(ContentLanguage.en),
      );
      when(
        () => client.postJson(
          '/articles/server-uuid-1/restore',
          null,
          query: any(named: 'query'),
          sessionFence: any(named: 'sessionFence'),
        ),
      ).thenAnswer((_) async => _articleMap(locale: 'zh-TW'));

      await dataSource.restoreArticle('server-uuid-1', locale: 'zh-TW');

      verify(
        () => client.postJson(
          '/articles/server-uuid-1/restore',
          null,
          query: {'locale': 'zh-TW'},
          sessionFence: any(named: 'sessionFence'),
        ),
      ).called(1);
    });
  });

  group('the cross-language list', () {
    test('reads every edition and keeps the server marker', () async {
      final dataSource = BlogRemoteDataSourceImpl(client);
      when(
        () => client.getEnvelopeForViewer(
          '/me/articles',
          expectedUserId: 'u1',
          query: any(named: 'query'),
        ),
      ).thenAnswer(
        (_) async => EnvelopeData(
          [
            _articleMap(locale: 'zh-CN'),
            {..._articleMap(locale: 'en'), 'title': 'An essay'},
          ],
          meta: const {
            'locales': ['zh-CN', 'zh-TW', 'en'],
          },
        ),
      );

      final editions = await dataSource.getMyArticleEditions(userId: 'u1');

      expect(editions.locales, ['zh-CN', 'zh-TW', 'en']);
      expect(editions.isConfirmed, isTrue);
      expect(editions.blogs.map((blog) => blog.locale), ['zh-CN', 'en']);
      expect(editions.blogs.map((blog) => blog.title), ['标题', 'An essay']);
      verify(
        () => client.getEnvelopeForViewer(
          '/me/articles',
          expectedUserId: 'u1',
          query: {'limit': '50', 'allLocales': 'true'},
        ),
      ).called(1);
    });

    test('an answer without the marker is not presented as complete', () async {
      final dataSource = BlogRemoteDataSourceImpl(client);
      when(
        () => client.getEnvelopeForViewer(
          '/me/articles',
          expectedUserId: 'u1',
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => EnvelopeData([_articleMap()]));

      final editions = await dataSource.getMyArticleEditions(userId: 'u1');

      expect(editions.isConfirmed, isFalse);
      expect(editions.locales, isNull);
      expect(editions.blogs.single.locale, 'zh-CN');
    });

    test(
      'a deployment without the route falls back to the public list',
      () async {
        final dataSource = BlogRemoteDataSourceImpl(client);
        when(
          () => client.getEnvelopeForViewer(
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

        final editions = await dataSource.getMyArticleEditions(userId: 'u1');

        expect(editions.locales, isNull);
        expect(editions.blogs.single.id, 'my-slug');
      },
    );

    test('a broken payload fails instead of returning a short list', () async {
      final dataSource = BlogRemoteDataSourceImpl(client);
      when(
        () => client.getEnvelopeForViewer(
          '/me/articles',
          expectedUserId: any(named: 'expectedUserId'),
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => EnvelopeData(const {'not': 'a list'}));

      await expectLater(
        () => dataSource.getMyArticleEditions(userId: 'u1'),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'code',
            'server.parse',
          ),
        ),
      );
    });
  });
}
