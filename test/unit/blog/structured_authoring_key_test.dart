import 'dart:async';

import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/editing/structured_authoring_key.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

class _Identity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 7;
  @override
  Stream<void> get identityChanges => const Stream.empty();
}

BlogModel _blog({
  String id = 'article-uuid',
  String author = 'author',
  String locale = 'en',
}) => BlogModel.fromNowaveArticle({
  ...structuredArticle(),
  'id': id,
  'authorId': author,
  'locale': locale,
});

void main() {
  late _Identity identity;
  setUp(() => identity = _Identity());

  test('structured authoring uses stable work ID, not public slug', () {
    final blog = _blog();
    final key = structuredAuthoringKey(
      blog: blog,
      signedInUserId: 'author',
      identity: identity,
    );
    expect(blog.id, 'structured');
    expect(blog.authoringArticleId, 'article-uuid');
    expect(key!.articleId, 'article-uuid');
    expect(key.userId, 'author');
    expect(key.locale, 'en');
  });

  test(
    'supported and unsupported structured documents can request exact recovery',
    () {
      final supported = _blog();
      expect(supported.document!.supported, isTrue);
      final unsupported = BlogModel.fromNowaveArticle({
        ...structuredArticle(),
        'id': 'article-uuid',
        'locale': 'en',
        'contentBlocksVersion': 99,
      });
      expect(unsupported.document!.supported, isFalse);
      expect(
        structuredAuthoringKey(
          blog: unsupported,
          signedInUserId: 'author',
          identity: identity,
        ),
        isNotNull,
      );
    },
  );

  test(
    'unknown, blank and whitespace IDs never become slug or recovery key',
    () {
      for (final id in ['', ' ', ' article-uuid', 'article-uuid ']) {
        final blog = _blog(id: id);
        expect(blog.authoringArticleId, isNull);
        expect(
          structuredAuthoringKey(
            blog: blog,
            signedInUserId: 'author',
            identity: identity,
          ),
          isNull,
        );
      }
    },
  );

  test('domain-only or legacy articles do not invent stable IDs', () {
    final blog = Blog(
      id: 'slug',
      title: 'title',
      content: 'text',
      posterId: 'author',
      imageUrl: '',
      tags: const [],
      updatedAt: DateTime.utc(2026),
      locale: 'en',
    );
    expect(blog.authoringArticleId, isNull);
    expect(
      structuredAuthoringKey(
        blog: blog,
        signedInUserId: 'author',
        identity: identity,
      ),
      isNull,
    );
  });

  test('plain Markdown stays on the ordinary editor path', () {
    final blog = BlogModel(
      id: 'slug',
      articleId: 'article-uuid',
      title: 'title',
      content: 'text',
      posterId: 'author',
      imageUrl: '',
      tags: const [],
      updatedAt: DateTime.utc(2026),
      locale: 'en',
    );
    expect(blog.document, isNull);
    expect(
      structuredAuthoringKey(
        blog: blog,
        signedInUserId: 'author',
        identity: identity,
      ),
      isNull,
    );
  });

  test('accepts only exact supported locale without default or fallback', () {
    for (final locale in ['zh-CN', 'zh-TW', 'en']) {
      final key = structuredAuthoringKey(
        blog: _blog(locale: locale),
        signedInUserId: 'author',
        identity: identity,
      );
      expect(key!.locale, locale);
    }
    for (final locale in ['', 'zh', 'en-US', ' en', 'zh-cn']) {
      expect(
        structuredAuthoringKey(
          blog: _blog(locale: locale),
          signedInUserId: 'author',
          identity: identity,
        ),
        isNull,
      );
    }
  });

  test(
    'requires the author, app account and live identity to agree exactly',
    () {
      for (final user in ['', ' author', 'other']) {
        expect(
          structuredAuthoringKey(
            blog: _blog(),
            signedInUserId: user,
            identity: identity,
          ),
          isNull,
        );
      }
      expect(
        structuredAuthoringKey(
          blog: _blog(author: 'other'),
          signedInUserId: 'author',
          identity: identity,
        ),
        isNull,
      );
      identity.activeUserId = 'other';
      expect(
        structuredAuthoringKey(
          blog: _blog(),
          signedInUserId: 'author',
          identity: identity,
        ),
        isNull,
      );
      identity.activeUserId = null;
      expect(
        structuredAuthoringKey(
          blog: _blog(),
          signedInUserId: 'author',
          identity: identity,
        ),
        isNull,
      );
    },
  );

  test('empty token refuses to open an authoring key', () {
    identity.accessToken = null;
    expect(
      structuredAuthoringKey(
        blog: _blog(),
        signedInUserId: 'author',
        identity: identity,
      ),
      isNull,
    );
    identity.accessToken = '';
    expect(
      structuredAuthoringKey(
        blog: _blog(),
        signedInUserId: 'author',
        identity: identity,
      ),
      isNull,
    );
  });

  test(
    'copy of a data model keeps its stable identity independent of slug',
    () {
      final copy = _blog().copyWith(id: 'renamed-slug');
      expect(copy.id, 'renamed-slug');
      expect(copy.authoringArticleId, 'article-uuid');
      expect(
        structuredAuthoringKey(
          blog: copy,
          signedInUserId: 'author',
          identity: identity,
        )!.articleId,
        'article-uuid',
      );
    },
  );
}
