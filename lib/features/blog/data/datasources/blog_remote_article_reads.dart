part of 'blog_remote_data_source.dart';

/// Read-only article routes extracted from [BlogRemoteDataSourceImpl].
///
/// Keeping pagination, locale selection and fallback rules together prevents a
/// write-focused change from accidentally altering public-feed cache semantics.
mixin _BlogRemoteReadOperations on _BlogRemoteOperationContext {
  Future<List<BlogModel>> getAllBlogs({required int page}) {
    return _guard(() async {
      final offset = (page - 1) * kBlogPageSize;
      final data = await retryOnConnectionClosed(
        () => client.getJson(
          '/articles',
          query: {
            'limit': '$kBlogPageSize',
            'offset': '$offset',
            'locale': _locale,
          },
        ),
      );
      return articlePayloadList(data);
    });
  }

  Future<LatestFeedSlice> getAllBlogsAfter({required String cursor}) async {
    final continuation = LatestFeedContinuation.tryDecode(cursor);
    if (continuation == null) throw const LatestFeedCursorUnavailable();
    try {
      final data = await retryOnConnectionClosed(
        () => client.getJson(
          '/articles',
          query: {
            'limit': '${continuation.requestLimit}',
            'cursor': continuation.apiCursor,
            'locale': _locale,
          },
        ),
      );
      if (data is! List || data.any((row) => row is! Map<String, dynamic>)) {
        throw const LatestFeedCursorUnavailable();
      }
      return continuation.advance(articlePayloadList(data));
    } on LatestFeedCursorUnavailable {
      rethrow;
    } on LatestFeedCursorTooDense {
      rethrow;
    } on NowaveApiException catch (error) {
      if (error.statusCode == 400 && error.code == 'BAD_USER_INPUT') {
        throw const LatestFeedCursorUnavailable();
      }
      throw mapToServerException(error);
    } catch (error) {
      throw mapToServerException(error);
    }
  }

  Future<List<BlogModel>> getOnlineFeed({
    required int page,
    required BlogFeedKind kind,
    String? expectedViewerId,
  }) async {
    if (kind == BlogFeedKind.latest) return getAllBlogs(page: page);
    try {
      final query = <String, String>{
        'limit': '$kBlogPageSize',
        'offset': '${(page - 1) * kBlogPageSize}',
        'locale': _locale,
        if (kind == BlogFeedKind.popular) 'sort': 'popular',
      };
      final dynamic data;
      if (kind == BlogFeedKind.following) {
        // Do not retry outside the identity fence: a new account could
        // otherwise be used for a retry of the previous viewer's request.
        data = await client.getJsonForViewer(
          '/me/feed',
          expectedUserId: expectedViewerId ?? '',
          query: query,
        );
      } else {
        final path = kind == BlogFeedKind.featured ? '/featured' : '/articles';
        data = await retryOnConnectionClosed(
          () => client.getJson(path, query: query),
        );
      }
      return articlePayloadList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  Future<BlogModel> getBlogById(
    String blogId, {
    NowaveSessionFence? sessionFence,
    String? locale,
  }) {
    return _guard(() async {
      final edition = _editionLocale(locale);
      final data = sessionFence == null
          ? await client.getJson(
              '/articles/$blogId',
              query: {'locale': edition},
            )
          : await client.getJson(
              '/articles/$blogId',
              query: {'locale': edition},
              sessionFence: sessionFence,
            );
      return BlogModel.fromNowaveArticle(articlePayloadMap(data));
    });
  }

  Future<List<BlogModel>> getRelatedArticles(String slug) {
    return _guard(() async {
      final data = await client.getJson(
        '/articles/$slug/related',
        query: {'limit': '$_kRelatedLimit', 'locale': _locale},
      );
      return articlePayloadList(data);
    });
  }

  Future<List<BlogModel>> getAuthorArticles(
    String posterId, {
    BlogFeedKind kind = BlogFeedKind.latest,
    int offset = 0,
    int limit = kAuthorPageSize,
  }) {
    return _guard(() async {
      final data = await client.getJson(
        '/authors/${Uri.encodeComponent(posterId)}/articles',
        query: {
          'limit': '$limit',
          'locale': _locale,
          if (kind == BlogFeedKind.popular) 'sort': 'popular',
          // The first page sends no offset: an older deployment ignores the
          // parameter and answers the first page anyway, which is the right
          // answer for it.
          if (offset > 0) 'offset': '$offset',
        },
      );
      return articlePayloadList(data);
    });
  }

  Future<List<BlogModel>> getBlogsByPosterId(String posterId) {
    return _guard(() async {
      final data = await client.getJson(
        '/authors/${Uri.encodeComponent(posterId)}/articles',
        query: {'limit': '$_kListLimit', 'locale': _locale},
      );
      return articlePayloadList(data);
    });
  }

  Future<List<BlogModel>> getMyArticles({required String userId}) async {
    try {
      final data = await client.getJsonForViewer(
        '/me/articles',
        expectedUserId: userId,
        query: {'limit': '$_kListLimit', 'locale': _locale},
      );
      return articlePayloadList(data);
    } on NowaveApiException catch (error) {
      // A deployment that predates the account-scoped list still serves the
      // public author list. "My articles" keeps working there; only server
      // drafts stay invisible, exactly as before.
      if (error.statusCode == 404 || error.statusCode == 405) {
        return getBlogsByPosterId(userId);
      }
      throw mapToServerException(error);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  Future<ArticleEditions> getMyArticleEditions({required String userId}) async {
    try {
      final envelope = await client.getEnvelopeForViewer(
        '/me/articles',
        expectedUserId: userId,
        query: {'limit': '$_kEditionsPerLocaleLimit', 'allLocales': 'true'},
      );
      final data = envelope.data;
      if (data is! List) {
        throw ServerException(
          '服务器返回了无法解析的数据',
          kind: FailureKind.server,
          code: 'server.parse',
          cause: data,
        );
      }
      final blogs = data
          .whereType<Map<String, dynamic>>()
          .map(BlogModel.fromNowaveArticle)
          .toList();
      return ArticleEditions(
        blogs: blogs,
        locales: _metaLocales(envelope.meta),
      );
    } on NowaveApiException catch (error) {
      // Same fallback as the single-locale list: a deployment without the
      // account-scoped route still serves the public author list, which has no
      // editions to tell apart, so the marker stays absent.
      if (error.statusCode == 404 || error.statusCode == 405) {
        return ArticleEditions(
          blogs: await getBlogsByPosterId(userId),
          locales: null,
        );
      }
      throw mapToServerException(error);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  /// The `meta.locales` marker, or null when the answer did not carry one.
  ///
  /// An older deployment ignores `allLocales` and answers the current language
  /// with no marker; treating that as a complete multi-language list would
  /// hide every other edition behind a confident empty result.
  List<String>? _metaLocales(Map<String, dynamic>? meta) {
    final raw = meta?['locales'];
    if (raw is! List) return null;
    final locales = raw
        .whereType<String>()
        .map((locale) => locale.trim())
        .where((locale) => locale.isNotEmpty)
        .toList();
    return locales.isEmpty ? null : locales;
  }

  Future<TagRef?> resolveTag(String name) async {
    final wanted = name.trim();
    if (wanted.isEmpty) return null;
    final wantedKey = wanted.toLowerCase();
    var offset = 0;
    try {
      // `query` is a server-side substring match, so the answer no longer
      // depends on where the tag sorts. Paging covers the pathological case
      // (a one-letter tag matching hundreds of taxonomies).
      for (var page = 0; page < _kTagLookupPages; page++) {
        final data = await client.getJson(
          '/tags',
          query: {
            'query': wanted,
            'limit': '$_kListLimit',
            'offset': '$offset',
            'locale': _locale,
          },
        );
        final tags = (data as List? ?? const []);
        for (final entry in tags.whereType<Map<String, dynamic>>()) {
          final tagName = (entry['name'] as String?)?.trim() ?? '';
          final slug = (entry['slug'] as String?)?.trim() ?? '';
          if (slug.isEmpty || tagName.isEmpty) continue;
          if (tagName.toLowerCase() == wantedKey) {
            return TagRef(name: tagName, slug: slug);
          }
        }
        if (tags.length < _kListLimit) return null;
        offset += _kListLimit;
      }
      // Bounded: a substring that still matches thousands of tags is not a
      // name anybody can browse to, and searching forever would hang the tap.
      return null;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  Future<List<BlogModel>> getArticlesByTag(
    String slug, {
    required int offset,
  }) async {
    try {
      final data = await client.getJson(
        '/tags/${Uri.encodeComponent(slug)}/articles',
        query: {
          'limit': '$kTagPageSize',
          'offset': '$offset',
          'locale': _locale,
        },
      );
      return articlePayloadList(data);
    } catch (e) {
      if (e is NowaveApiException && e.statusCode == 404) {
        // The tag disappeared between resolving it and reading its page.
        throw const ServerException(
          '这个标签已不存在',
          kind: FailureKind.server,
          code: 'tag.notFound',
        );
      }
      throw mapToServerException(e);
    }
  }

  Future<List<BlogModel>> searchBlogs(String query) {
    return _guard(() async {
      final sanitizedQuery = query.trim();
      if (sanitizedQuery.isEmpty) {
        return const <BlogModel>[];
      }
      final data = await client.getJson(
        '/articles',
        query: {
          'query': sanitizedQuery,
          'limit': '$kMaxSearchResults',
          'locale': _locale,
        },
      );
      return articlePayloadList(data);
    });
  }
}
