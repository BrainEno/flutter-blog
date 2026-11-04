import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/utils/retry_on_connection_closed.dart';
import 'package:belog/features/blog/data/datasources/article_like_store.dart';
import 'package:belog/features/blog/data/datasources/article_payload.dart';
import 'package:belog/features/blog/data/datasources/latest_feed_cursor.dart';
import 'package:belog/features/blog/data/datasources/tag_resolver.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/models/deleted_blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/tag_paging.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart'
    show kBlogPageSize;
import 'package:belog/features/blog/domain/usecase/search_blogs.dart'
    show kMaxSearchResults;
import 'package:belog/core/common/entities/image_upload.dart';

/// Remote data source against the no-wave `apps/api` REST backend.
///
/// Addressing rules (see docs/supabase-to-nowave-migration.md):
/// - public reads and likes address an article by its slug, which is
///   [Blog.id] in this app,
/// - `PUT /articles/:articleId` updates by the server UUID, kept on
///   [BlogModel.articleId].
abstract interface class BlogRemoteDataSource {
  /// Creates the article (`POST /articles`). [blog.imageUrl] must already
  /// be an immutable media URL from [uploadBlogImage] (or empty: articles
  /// without covers are published as text-only content blocks).
  Future<BlogModel> uploadBlog(
    BlogModel blog, {
    NowaveSessionFence? sessionFence,
  });

  /// Uploads a cover image (`POST /me/media`, raw bytes + MIME type) and
  /// returns its immutable public URL. The server re-encodes to WebP.
  Future<String> uploadBlogImage({
    required ImageUpload image,
    NowaveSessionFence? sessionFence,
  });

  Future<List<BlogModel>> getAllBlogs({required int page});

  /// Continues the latest online feed using a local, overlap-aware token.
  /// A rejected/ignored cursor or an unsafe dense boundary is explicit.
  Future<LatestFeedSlice> getAllBlogsAfter({required String cursor});

  /// Fetches a server-ranked or authenticated following page.
  Future<List<BlogModel>> getOnlineFeed({
    required int page,
    required BlogFeedKind kind,
    String? expectedViewerId,
  });

  /// Loads an article by its public slug ([Blog.id]).
  Future<BlogModel> getBlogById(
    String blogId, {
    NowaveSessionFence? sessionFence,
  });

  /// Same-topic articles the server recommends next to [slug]
  /// (`GET /articles/:slug/related`).
  Future<List<BlogModel>> getRelatedArticles(String slug);
  Future<List<BlogModel>> getBlogsByPosterId(String posterId);

  /// The viewer's own articles, including server-side drafts
  /// (`GET /me/articles`, newest update first).
  ///
  /// Unlike [getBlogsByPosterId] this is an account-scoped read: it is fenced
  /// to [userId] so a list for another account is never returned, and it does
  /// not follow redirects, which would forward the bearer token. Drafts are
  /// private content and are never written to the shared article cache.
  Future<List<BlogModel>> getMyArticles({required String userId});

  /// Resolves a stored tag name to its server taxonomy.
  ///
  /// The slug is server-generated, so it has to be looked up. The lookup is
  /// server-side (`query=`) and pages while results come back full: a tag
  /// that sorts past the first 100 must still resolve (#106). Null means the
  /// server has no such tag - callers must show an explicit empty state and
  /// never fall back to "everything".
  Future<TagRef?> resolveTag(String name);

  /// One page of a tag's published articles (`GET /tags/:slug/articles`),
  /// newest first. Throws `tag.notFound` when the tag itself is gone, which
  /// is distinct from a tag that exists with nothing filed under it.
  Future<List<BlogModel>> getArticlesByTag(String slug, {required int offset});
  Future<List<BlogModel>> searchBlogs(String query);
  Future<BlogModel> editBlog(
    BlogModel blog, {
    NowaveSessionFence? sessionFence,
  });

  /// Soft-deletes an article (`DELETE /articles/:articleId`): the row
  /// becomes a tombstone, leaves every list and moves to the author's
  /// recycle bin until the server sweep purges it. [articleId] is the
  /// server UUID ([BlogModel.articleId]), not the slug.
  Future<bool> deleteArticle(String articleId);

  /// Lists the author's own tombstones (`GET /me/articles/deleted`),
  /// most recently deleted first, each with the server-computed purge
  /// deadline.
  Future<List<DeletedBlog>> getDeletedBlogs();

  /// Restores a tombstone (`POST /articles/:articleId/restore`); the
  /// article comes back as a draft with its original slug reclaimed
  /// when it is still free.
  Future<BlogModel> restoreArticle(String articleId);
  Future<List<BlogModel>> getUserLikedBlogs(String userId);

  /// Sets the like to the opposite of the current server state and returns
  /// the state after the operation (true = liked).
  Future<bool> toggleLikeBlog(String userId, String blogId);
  Future<bool> isBlogLikedByUser(String userId, String blogId);
}

/// Upper bound for author/tag/liked listings (the API caps `limit` at 100).
const int _kListLimit = 100;

/// How many taxonomy pages a name lookup may walk before giving up.
const int _kTagLookupPages = 5;

/// Related articles are a reading suggestion rider (issue #19), not a
/// primary list: the server caps the endpoint at 50, we show a handful.
const int _kRelatedLimit = 6;

class BlogRemoteDataSourceImpl implements BlogRemoteDataSource {
  final NowaveApiClient client;

  /// Where the *active* account is read from.
  ///
  /// Every `/me`-scoped route answers for whoever holds the bearer token, so
  /// an operation has to name the account it believes it is serving. With no
  /// identity the app would be trusting the token holder implicitly - the gap
  /// in #104 - so the app always passes one; tests that predate the fence may
  /// omit it and keep the old behaviour.
  final NowaveSessionIdentity? identity;

  BlogRemoteDataSourceImpl(this.client, {this.identity});

  /// Tag name -> id resolution, cached for the app session.
  late final NowaveTagResolver _tags = NowaveTagResolver(client);

  /// The viewer's like state, with one in-flight toggle per article.
  late final ArticleLikeStore _likes = ArticleLikeStore(
    client: client,
    requireActiveFence: requireActiveFence,
    identity: identity,
  );

  /// The account a `/me`-scoped call is made for, right now.
  ///
  /// Refused when nobody is signed in: sending the request anyway would run it
  /// for an account the caller never meant to act as.
  NowaveSessionFence requireActiveFence() {
    final active = identity;
    final userId = active?.activeUserId ?? '';
    if (active == null || userId.isEmpty) {
      throw const NowaveApiException(
        statusCode: HttpStatus.unauthorized,
        code: 'UNAUTHENTICATED',
        message: 'No account is active for this operation.',
      );
    }
    return NowaveSessionFence(
      userId: userId,
      generation: active.sessionGeneration,
    );
  }

  @override
  Future<BlogModel> uploadBlog(
    BlogModel blog, {
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      final tagIds = await _tags.resolveIds(blog.tags, sessionFence);
      final body = <String, dynamic>{
        'title': blog.title,
        'contentBlocks': blogToContentBlocks(
          content: blog.content,
          coverUrl: blog.imageUrl.isNotEmpty ? blog.imageUrl : null,
        ),
        'contentBlocksVersion': 0,
        'publish': true,
        'locale': 'zh-CN',
        if (tagIds.isNotEmpty) 'tagIds': tagIds,
      };
      final data = sessionFence == null
          ? await client.postJson('/articles', body)
          : await client.postJson(
              '/articles',
              body,
              sessionFence: sessionFence,
            );
      return BlogModel.fromNowaveArticle(articlePayloadMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<String> uploadBlogImage({
    required ImageUpload image,
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      // A lost response does not prove the upload failed: the server may
      // already have stored a new asset. Media has no idempotency key yet,
      // so do not silently create another one on a transport retry.
      final asset = sessionFence == null
          ? await client.uploadMedia(image.bytes, image.mimeType)
          : await client.uploadMedia(
              image.bytes,
              image.mimeType,
              sessionFence: sessionFence,
            );
      return client.mediaUri(asset.id).toString();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getAllBlogs({required int page}) async {
    try {
      final offset = (page - 1) * kBlogPageSize;
      final data = await retryOnConnectionClosed(
        () => client.getJson(
          '/articles',
          query: {
            'limit': '$kBlogPageSize',
            'offset': '$offset',
            'locale': 'zh-CN',
          },
        ),
      );
      return articlePayloadList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
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
            'locale': 'zh-CN',
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
      if (error.statusCode == HttpStatus.badRequest &&
          error.code == 'BAD_USER_INPUT') {
        throw const LatestFeedCursorUnavailable();
      }
      throw mapToServerException(error);
    } catch (error) {
      throw mapToServerException(error);
    }
  }

  @override
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
        'locale': 'zh-CN',
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

  @override
  Future<BlogModel> getBlogById(
    String blogId, {
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      final data = sessionFence == null
          ? await client.getJson(
              '/articles/$blogId',
              query: {'locale': 'zh-CN'},
            )
          : await client.getJson(
              '/articles/$blogId',
              query: {'locale': 'zh-CN'},
              sessionFence: sessionFence,
            );
      return BlogModel.fromNowaveArticle(articlePayloadMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getRelatedArticles(String slug) async {
    try {
      final data = await client.getJson(
        '/articles/$slug/related',
        query: {'limit': '$_kRelatedLimit', 'locale': 'zh-CN'},
      );
      return articlePayloadList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByPosterId(String posterId) async {
    try {
      final data = await client.getJson(
        '/authors/${Uri.encodeComponent(posterId)}/articles',
        query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
      );
      return articlePayloadList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getMyArticles({required String userId}) async {
    try {
      final data = await client.getJsonForViewer(
        '/me/articles',
        expectedUserId: userId,
        query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
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

  @override
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
            'locale': 'zh-CN',
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

  @override
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
          'locale': 'zh-CN',
        },
      );
      return articlePayloadList(data);
    } catch (e) {
      if (e is NowaveApiException && e.statusCode == HttpStatus.notFound) {
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

  @override
  Future<List<BlogModel>> searchBlogs(String query) async {
    try {
      final sanitizedQuery = query.trim();
      if (sanitizedQuery.isEmpty) {
        return const <BlogModel>[];
      }
      final data = await client.getJson(
        '/articles',
        query: {
          'query': sanitizedQuery,
          'limit': '$kMaxSearchResults',
          'locale': 'zh-CN',
        },
      );
      return articlePayloadList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<BlogModel> editBlog(
    BlogModel blog, {
    NowaveSessionFence? sessionFence,
  }) async {
    try {
      if (blog.articleId.isEmpty) {
        throw const ServerException(
          '该文章缺少服务端编号，无法更新，请尝试重新打开后再编辑',
          kind: FailureKind.validation,
          code: 'article.idUpdate',
        );
      }
      if (!blog.plainEditorCompatible || blog.serverSummary == null) {
        throw const ServerException(
          '无法安全保留这篇文章的正文或摘要，请在 no-wave 网页编辑',
          kind: FailureKind.validation,
          code: 'article.structuredEditUnsupported',
        );
      }
      final tagIds = await _tags.resolveIds(blog.tags, sessionFence);
      final body = <String, dynamic>{
        'slug': blog.id,
        'title': blog.title,
        // Preserve the freshly fetched server summary. An empty value may
        // still be regenerated by no-wave's write normalization.
        'summary': blog.serverSummary,
        'contentBlocks': blogToContentBlocks(
          content: blog.content,
          coverUrl: blog.imageUrl.isNotEmpty ? blog.imageUrl : null,
        ),
        'contentBlocksVersion': 0,
        'publish': true,
        'locale': 'zh-CN',
        if (tagIds.isNotEmpty) 'tagIds': tagIds,
      };
      final data = sessionFence == null
          ? await client.putJson('/articles/${blog.articleId}', body)
          : await client.putJson(
              '/articles/${blog.articleId}',
              body,
              sessionFence: sessionFence,
            );
      return BlogModel.fromNowaveArticle(articlePayloadMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> deleteArticle(String articleId) async {
    try {
      if (articleId.isEmpty) {
        throw const ServerException(
          '该文章缺少服务端编号，无法删除',
          kind: FailureKind.validation,
          code: 'article.idDelete',
        );
      }
      // 200 with `{id, deletedAt}` means tombstoned; every other outcome
      // (404 not-yours-or-gone, 403 foreign author, ...) throws. The fence
      // makes a page belonging to an old account refuse to delete into the
      // new one, and the client refuses if the account changes mid-flight.
      final fence = identity == null ? null : requireActiveFence();
      await client.deleteJson('/articles/$articleId', sessionFence: fence);
      return true;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<DeletedBlog>> getDeletedBlogs() async {
    try {
      final fence = identity == null ? null : requireActiveFence();
      final data = await retryOnConnectionClosed(
        () => fence == null
            ? client.getJson(
                '/me/articles/deleted',
                query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
              )
            : client.getJsonForViewer(
                '/me/articles/deleted',
                expectedUserId: fence.userId,
                query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
              ),
      );
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(DeletedBlogModel.fromNowaveArticle)
            .toList();
      }
      throw ServerException(
        '服务器返回了无法解析的数据',
        kind: FailureKind.server,
        code: 'server.parse',
        cause: data,
      );
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<BlogModel> restoreArticle(String articleId) async {
    try {
      if (articleId.isEmpty) {
        throw const ServerException(
          '该文章缺少服务端编号，无法恢复',
          kind: FailureKind.validation,
          code: 'article.idRestore',
        );
      }
      // The restore route reads the locale from the query string.
      final fence = identity == null ? null : requireActiveFence();
      final data = await client.postJson(
        '/articles/$articleId/restore',
        null,
        query: {'locale': 'zh-CN'},
        sessionFence: fence,
      );
      return BlogModel.fromNowaveArticle(articlePayloadMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getUserLikedBlogs(String userId) async {
    try {
      // `/me/liked-articles` answers for the token holder, so the requested
      // account and the active one must agree - otherwise B's likes would be
      // shown as A's page (#104).
      final data = identity == null
          ? await retryOnConnectionClosed(
              () => client.getJson(
                '/me/liked-articles',
                query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
              ),
            )
          : await retryOnConnectionClosed(
              () => client.getJsonForViewer(
                '/me/liked-articles',
                expectedUserId: userId,
                query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
              ),
            );
      return articlePayloadList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> toggleLikeBlog(String userId, String blogId) =>
      _likes.toggle(userId, blogId);

  @override
  Future<bool> isBlogLikedByUser(String userId, String blogId) =>
      _likes.isLiked(userId, blogId);
}
