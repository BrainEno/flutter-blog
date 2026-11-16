import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
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
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/author_articles_paging.dart';
import 'package:belog/features/blog/domain/entities/deleted_blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/tag_paging.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart'
    show kBlogPageSize;
import 'package:belog/features/blog/domain/usecase/search_blogs.dart'
    show kMaxSearchResults;
import 'package:belog/core/common/entities/image_upload.dart';

part 'blog_remote_article_reads.dart';
part 'blog_remote_article_writes.dart';

// HTTP status codes are spelled out below (401/400/404) so the file does not
// have to import `dart:io` just for its constants.
//
// Remote data source against the no-wave `apps/api` REST backend.
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
  ///
  /// [categoryIds] is the author's choice from the editor. Null (the default)
  /// means the picker was never touched and the field is left out of the
  /// request entirely - categories are editorial structure (ADR 0016), so an
  /// app that guessed would either invent one or drop the real one. An empty
  /// list is the author explicitly choosing none.
  Future<BlogModel> uploadBlog(
    BlogModel blog, {
    NowaveSessionFence? sessionFence,
    String? idempotencyKey,
    List<String>? categoryIds,
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
  ///
  /// [locale] names the edition to read. Null means the current content
  /// language; pass the edition's own locale when a caller already knows it,
  /// or the body it gets back may belong to a different translation.
  Future<BlogModel> getBlogById(
    String blogId, {
    NowaveSessionFence? sessionFence,
    String? locale,
  });

  /// Same-topic articles the server recommends next to [slug]
  /// (`GET /articles/:slug/related`).
  Future<List<BlogModel>> getRelatedArticles(String slug);

  /// One page of an author's published work (`GET /authors/:id/articles`).
  ///
  /// The route accepts `sort` and `offset`: `latest` pages by publication date,
  /// `popular` by saves and stops at [kAuthorPopularMaxOffset]. The older
  /// one-shot read stays as [getBlogsByPosterId] for callers that want the
  /// author's most recent 100 rows in one request (the account list fallback).
  Future<List<BlogModel>> getAuthorArticles(
    String posterId, {
    BlogFeedKind kind = BlogFeedKind.latest,
    int offset = 0,
    int limit = kAuthorPageSize,
  });

  Future<List<BlogModel>> getBlogsByPosterId(String posterId);

  /// The viewer's own articles, including server-side drafts
  /// (`GET /me/articles`, newest update first).
  ///
  /// Unlike [getBlogsByPosterId] this is an account-scoped read: it is fenced
  /// to [userId] so a list for another account is never returned, and it does
  /// not follow redirects, which would forward the bearer token. Drafts are
  /// private content and are never written to the shared article cache.
  Future<List<BlogModel>> getMyArticles({required String userId});

  /// The same account-scoped list read across every language edition
  /// (`GET /me/articles?allLocales=true`).
  ///
  /// The server returns each edition independently, newest update first, and
  /// marks the locales it read in `meta.locales`. A deployment that predates
  /// the parameter ignores it and answers the single current language with no
  /// marker; [ArticleEditions.locales] is null in that case, so the caller can
  /// say "only one language here" instead of implying a complete list.
  Future<ArticleEditions> getMyArticleEditions({required String userId});

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

  /// Same `categoryIds` rule as [uploadBlog]: null leaves the article's
  /// categories alone, an empty list clears them, one id replaces them.
  Future<BlogModel> editBlog(
    BlogModel blog, {
    ArticleRevision? expectedRevision,
    NowaveSessionFence? sessionFence,
    List<String>? categoryIds,
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
  Future<BlogModel> restoreArticle(String articleId, {String? locale});
  Future<List<BlogModel>> getUserLikedBlogs(String userId);

  /// Sets the like to the opposite of the current server state and returns
  /// the state after the operation (true = liked).
  Future<bool> toggleLikeBlog(String userId, String blogId);
  Future<bool> isBlogLikedByUser(String userId, String blogId);
}

/// Upper bound for author/tag/liked listings (the API caps `limit` at 100).
const int _kListLimit = 100;

/// How many editions one language may contribute to the cross-language
/// "my articles" read. The server applies `limit` per locale there, so this
/// is a per-language cap, not a total (three locales can return 150 rows).
const int _kEditionsPerLocaleLimit = 50;

/// How many taxonomy pages a name lookup may walk before giving up.
const int _kTagLookupPages = 5;

/// Related articles are a reading suggestion rider (issue #19), not a
/// primary list: the server caps the endpoint at 50, we show a handful.
const int _kRelatedLimit = 6;

/// The narrow shared contract for the extracted read/write operation mixins.
///
/// It deliberately exposes only transport, locale, taxonomy and session-fence
/// primitives. Public operations remain in the mixins or the façade, so a
/// future change cannot quietly couple a read route to a write implementation.
abstract class _BlogRemoteOperationContext {
  NowaveApiClient get client;
  NowaveSessionIdentity? get identity;
  String get _locale;
  NowaveTagResolver get _tags;
  Future<T> _guard<T>(Future<T> Function() body);
  NowaveSessionFence requireActiveFence();
  String _editionLocale(String? locale);
}

class BlogRemoteDataSourceImpl extends _BlogRemoteOperationContext
    with _BlogRemoteReadOperations, _BlogRemoteWriteOperations
    implements BlogRemoteDataSource {
  final NowaveApiClient client;

  /// Where the *active* account is read from.
  ///
  /// Every `/me`-scoped route answers for whoever holds the bearer token, so
  /// an operation has to name the account it believes it is serving. With no
  /// identity the app would be trusting the token holder implicitly - the gap
  /// in #104 - so the app always passes one; tests that predate the fence may
  /// omit it and keep the old behaviour.
  final NowaveSessionIdentity? identity;

  BlogRemoteDataSourceImpl(this.client, {this.identity, this.contentLocale});

  /// Content language for the requests this data source makes; null keeps the
  /// historical Chinese default for callers that never switch (tests).
  final ContentLocale? contentLocale;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  /// Tag name -> id resolution, cached for the app session.
  late final NowaveTagResolver _tags = NowaveTagResolver(client);

  /// The viewer's like state, with one in-flight toggle per article.
  late final ArticleLikeStore _likes = ArticleLikeStore(
    client: client,
    requireActiveFence: requireActiveFence,
    identity: identity,
    contentLocale: contentLocale,
  );

  /// Runs one request and translates every failure into this layer's
  /// exception contract.
  ///
  /// Every public method here has the same boundary - transport and decoding
  /// errors in, `ServerException` out - so the mapping lives in one place
  /// instead of a `try`/`catch` wrapped around each body. The methods that
  /// decide something *before* the first request keep their own handler:
  /// `getOnlineFeed` chooses the path, `getArticlesByTag` adds a 404 case and
  /// `resolveTag` normalises the query first.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  /// The account a `/me`-scoped call is made for, right now.
  ///
  /// Refused when nobody is signed in: sending the request anyway would run it
  /// for an account the caller never meant to act as.
  NowaveSessionFence requireActiveFence() {
    final active = identity;
    final userId = active?.activeUserId ?? '';
    if (active == null || userId.isEmpty) {
      throw const NowaveApiException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'No account is active for this operation.',
      );
    }
    return NowaveSessionFence(
      userId: userId,
      generation: active.sessionGeneration,
    );
  }

  /// The locale a write must name: the edition a caller handed us when it
  /// knows one, otherwise the content language in effect.
  ///
  /// The server treats an omitted `locale` on an article write as `zh-CN`, so
  /// silently dropping the edition would rewrite the wrong translation.
  String _editionLocale(String? locale) {
    final trimmed = locale?.trim() ?? '';
    return trimmed.isEmpty ? _locale : trimmed;
  }

  @override
  Future<List<BlogModel>> getUserLikedBlogs(String userId) {
    return _guard(() async {
      // `/me/liked-articles` answers for the token holder, so the requested
      // account and the active one must agree - otherwise B's likes would be
      // shown as A's page (#104).
      final data = identity == null
          ? await retryOnConnectionClosed(
              () => client.getJson(
                '/me/liked-articles',
                query: {'limit': '$_kListLimit', 'locale': _locale},
              ),
            )
          : await retryOnConnectionClosed(
              () => client.getJsonForViewer(
                '/me/liked-articles',
                expectedUserId: userId,
                query: {'limit': '$_kListLimit', 'locale': _locale},
              ),
            );
      return articlePayloadList(data);
    });
  }

  @override
  Future<bool> toggleLikeBlog(String userId, String blogId) =>
      _likes.toggle(userId, blogId);

  @override
  Future<bool> isBlogLikedByUser(String userId, String blogId) =>
      _likes.isLiked(userId, blogId);
}
