import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/utils/retry_on_connection_closed.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/models/deleted_blog_model.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart'
    show kBlogPageSize;

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
  Future<BlogModel> uploadBlog(BlogModel blog);

  /// Uploads a cover image (`POST /me/media`, raw bytes + MIME type) and
  /// returns its immutable public URL. The server re-encodes to WebP.
  Future<String> uploadBlogImage({required File image, String? mimeType});

  Future<List<BlogModel>> getAllBlogs({required int page});

  /// Loads an article by its public slug ([Blog.id]).
  Future<BlogModel> getBlogById(String blogId);
  Future<List<BlogModel>> getBlogsByPosterId(String posterId);
  Future<List<BlogModel>> getBlogsByTag(String tag);
  Future<List<BlogModel>> searchBlogs(String query);
  Future<BlogModel> editBlog(BlogModel blog);

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

/// Upper bound for search results (the API accepts up to 100).
const int kMaxSearchResults = 50;

/// Upper bound for author/tag/liked listings (the API caps `limit` at 100).
const int _kListLimit = 100;

class BlogRemoteDataSourceImpl implements BlogRemoteDataSource {
  final NowaveApiClient client;
  BlogRemoteDataSourceImpl(this.client);

  /// In-memory cache of tag name -> tag object, so publishing several
  /// articles does not re-create/resolve the same tags each time.
  final Map<String, Map<String, dynamic>> _tagByName = {};

  /// In-flight `POST /tags` resolutions by tag name, so concurrent
  /// publishes share one request per name.
  final Map<String, Future<Map<String, dynamic>>> _tagLookups = {};

  /// One in-flight like toggle per article. The API sets an explicit like
  /// state rather than toggling, so two overlapping read-then-write pairs
  /// would both read the same `current` and write the same new state -
  /// silently dropping one of the taps. Serializing per slug keeps every
  /// tap meaningful.
  final Map<String, Future<bool>> _likeToggleBySlug = {};

  @override
  Future<BlogModel> uploadBlog(BlogModel blog) async {
    try {
      final tagIds = await _resolveTagIds(blog.tags);
      final data = await client.postJson('/articles', <String, dynamic>{
        'title': blog.title,
        'contentBlocks': blogToContentBlocks(
          content: blog.content,
          coverUrl: blog.imageUrl.isNotEmpty ? blog.imageUrl : null,
        ),
        'contentBlocksVersion': 0,
        'publish': true,
        'locale': 'zh-CN',
        if (tagIds.isNotEmpty) 'tagIds': tagIds,
      });
      return BlogModel.fromNowaveArticle(_articleMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<String> uploadBlogImage({
    required File image,
    String? mimeType,
  }) async {
    try {
      final bytes = await image.readAsBytes();
      final asset = await retryOnConnectionClosed(() async {
        return client.uploadMedia(bytes, mimeType ?? 'image/jpeg');
      });
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
      return _articleList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<BlogModel> getBlogById(String blogId) async {
    try {
      final data = await client.getJson(
        '/articles/$blogId',
        query: {'locale': 'zh-CN'},
      );
      return BlogModel.fromNowaveArticle(_articleMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByPosterId(String posterId) async {
    try {
      final data = await client.getJson(
        '/authors/$posterId/articles',
        query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
      );
      return _articleList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByTag(String tag) async {
    try {
      final slug = await _tagSlugByName(tag);
      if (slug == null) {
        // Unknown tag: nothing has been filed under it yet.
        return const <BlogModel>[];
      }
      final data = await client.getJson(
        '/tags/$slug/articles',
        query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
      );
      return _articleList(data);
    } catch (e) {
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
      return _articleList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<BlogModel> editBlog(BlogModel blog) async {
    try {
      if (blog.articleId.isEmpty) {
        throw const ServerException(
          '该文章缺少服务端编号，无法更新，请尝试重新打开后再编辑',
          kind: FailureKind.validation,
        );
      }
      final tagIds = await _resolveTagIds(blog.tags);
      final data = await client.putJson('/articles/${blog.articleId}', {
        'slug': blog.id,
        'title': blog.title,
        'contentBlocks': blogToContentBlocks(
          content: blog.content,
          coverUrl: blog.imageUrl.isNotEmpty ? blog.imageUrl : null,
        ),
        'contentBlocksVersion': 0,
        'publish': true,
        'locale': 'zh-CN',
        if (tagIds.isNotEmpty) 'tagIds': tagIds,
      });
      return BlogModel.fromNowaveArticle(_articleMap(data));
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
        );
      }
      // 200 with `{id, deletedAt}` means tombstoned; every other outcome
      // (404 not-yours-or-gone, 403 foreign author, ...) throws.
      await client.deleteJson('/articles/$articleId');
      return true;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<DeletedBlog>> getDeletedBlogs() async {
    try {
      final data = await retryOnConnectionClosed(
        () => client.getJson(
          '/me/articles/deleted',
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
        );
      }
      // The restore route reads the locale from the query string.
      final data = await client.postJson(
        '/articles/$articleId/restore',
        null,
        query: {'locale': 'zh-CN'},
      );
      return BlogModel.fromNowaveArticle(_articleMap(data));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getUserLikedBlogs(String userId) async {
    try {
      final data = await retryOnConnectionClosed(
        () => client.getJson(
          '/me/liked-articles',
          query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
        ),
      );
      return _articleList(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> toggleLikeBlog(String userId, String blogId) {
    // Share the in-flight toggle so concurrent callers queue behind it
    // instead of racing each other; the slot frees on completion.
    final inFlight = _likeToggleBySlug[blogId];
    if (inFlight != null) {
      return inFlight;
    }
    return _likeToggleBySlug[blogId] = _toggleLike(blogId).whenComplete(() {
      _likeToggleBySlug.remove(blogId);
    });
  }

  Future<bool> _toggleLike(String blogId) async {
    try {
      // The API sets an explicit like state rather than toggling, so the
      // current server state is read first and the opposite is written.
      // The response is the authoritative post-state.
      final current = await _likeInfo(blogId);
      final data = await client.putJson('/articles/$blogId/like', {
        'liked': !current,
      });
      final map = _articleMap(data);
      return map['likedByViewer'] as bool? ?? !current;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> isBlogLikedByUser(String userId, String blogId) async {
    try {
      return await _likeInfo(blogId);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  Future<bool> _likeInfo(String slug) async {
    final data = await client.getJson(
      '/articles/$slug/like',
      query: {'locale': 'zh-CN'},
    );
    return _articleMap(data)['likedByViewer'] as bool? ?? false;
  }

  /// Resolves tag names to tag ids via `POST /tags` (create-or-reuse), with
  /// an in-memory cache. Concurrent calls for the same name share one
  /// request (the create-or-reuse endpoint is idempotent, but halving the
  /// traffic is still worth it).
  Future<List<String>> _resolveTagIds(List<String> tags) async {
    final names = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (names.isEmpty) return const <String>[];
    final ids = <String>[];
    for (final name in names) {
      final cached = _tagByName[name];
      if (cached != null) {
        ids.add(cached['id'] as String);
        continue;
      }
      final lookup = _claimTag(name);
      final tag = await lookup;
      _tagByName[name] = tag;
      ids.add(tag['id'] as String);
    }
    return ids;
  }

  /// Returns the in-flight (or freshly started) resolution for [name].
  ///
  /// The slot is released on success AND failure: a failed resolution
  /// must not poison the name for the rest of the app session, it just
  /// propagates its error to whoever joined it.
  Future<Map<String, dynamic>> _claimTag(String name) {
    final inFlight = _tagLookups[name];
    if (inFlight != null) {
      return inFlight;
    }
    return _tagLookups[name] = _resolveTag(name).whenComplete(() {
      _tagLookups.remove(name);
    });
  }

  Future<Map<String, dynamic>> _resolveTag(String name) async {
    final data = await client.postJson('/tags', {'name': name});
    return _articleMap(data);
  }

  /// Resolves a tag name to its slug via the public `GET /tags` listing
  /// (the slug is a server-generated opaque value and cannot be derived
  /// from the display name client-side).
  Future<String?> _tagSlugByName(String name) async {
    final wanted = name.trim();
    if (wanted.isEmpty) return null;
    final data = await client.getJson(
      '/tags',
      query: {'limit': '$_kListLimit', 'locale': 'zh-CN'},
    );
    final tags = (data as List? ?? const []);
    for (final tag in tags) {
      final map = tag as Map<String, dynamic>;
      if ((map['name'] as String?)?.trim() == wanted) {
        return map['slug'] as String?;
      }
    }
    return null;
  }

  Map<String, dynamic> _articleMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw ServerException(
      '服务器返回了无法解析的数据',
      kind: FailureKind.server,
      cause: data,
    );
  }

  List<BlogModel> _articleList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(BlogModel.fromNowaveArticle)
          .toList();
    }
    throw ServerException(
      '服务器返回了无法解析的数据',
      kind: FailureKind.server,
      cause: data,
    );
  }
}
