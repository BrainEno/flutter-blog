import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/article_payload.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/category_paging.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:http/http.dart' as http;

/// Category browsing against no-wave's public `/categories` routes.
abstract interface class CategoryRemoteDataSource {
  /// `GET /categories`: the catalog in the requested content language.
  Future<List<CategoryRef>> listCategories();

  /// `GET /categories/:slug`: null when the server has no such category.
  Future<CategoryRef?> getCategory(String slug);

  /// `GET /categories/:slug/articles`: one page, newest first.
  Future<List<BlogModel>> getArticlesByCategory(
    String slug, {
    required int offset,
  });
}

/// These reads are public, so they use their own client without an
/// authenticator: a signed-in reader's token is never attached to a category
/// request and no refresh can be triggered by one.
class CategoryRemoteDataSourceImpl implements CategoryRemoteDataSource {
  CategoryRemoteDataSourceImpl({
    required Uri baseUrl,
    http.Client? httpClient,
    this.contentLocale,
  }) : _client = NowaveApiClient(baseUrl: baseUrl, httpClient: httpClient);

  /// Content language for the requests this data source makes; null keeps the
  /// historical Chinese default for callers that never switch (tests).
  final ContentLocale? contentLocale;

  final NowaveApiClient _client;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  static const _invalidResponse = ServerException(
    '服务器返回了无法解析的数据',
    code: 'server.parse',
  );

  static const _categoryNotFound = ServerException(
    '这个分类已不存在',
    kind: FailureKind.server,
    code: 'category.notFound',
  );

  // Slugs are opaque path segments, but a dot segment can be normalized away
  // by a URI stack before the category route is reached.
  static bool _isUsableSlug(String value) =>
      value.isNotEmpty &&
      value.length <= 300 &&
      value == value.trim() &&
      value != '.' &&
      value != '..';

  @override
  Future<List<CategoryRef>> listCategories() async {
    try {
      final data = await _client.getJson(
        '/categories',
        query: {
          'limit': '$kCategoryListLimit',
          'offset': '0',
          'locale': _locale,
        },
      );
      if (data is! List || data.length > kCategoryListLimit) {
        throw _invalidResponse;
      }
      final seen = <String>{};
      final categories = <CategoryRef>[];
      for (final value in data) {
        final category = _parseCategory(value);
        // A repeated slug would be a different row with the same address;
        // keeping one of them silently would misreport the catalog.
        if (!seen.add(category.slug)) throw _invalidResponse;
        categories.add(category);
      }
      return List.unmodifiable(categories);
    } catch (error) {
      // A deployment can predate the /categories routes. A 404/405 there says
      // nothing about the version, so the page may only claim "not offered".
      if (error is NowaveApiException &&
          (error.statusCode == 404 || error.statusCode == 405)) {
        throw const ServerException(
          '此服务器暂不提供分类',
          kind: FailureKind.server,
          code: 'categories.unavailable',
        );
      }
      throw mapToServerException(error);
    }
  }

  @override
  Future<CategoryRef?> getCategory(String slug) async {
    final wanted = slug.trim();
    if (!_isUsableSlug(wanted)) {
      throw const ServerException(
        '分类标识无效',
        kind: FailureKind.validation,
        code: 'client.validation',
      );
    }
    try {
      final data = await _client.getJson(
        '/categories/${Uri.encodeComponent(wanted)}',
        query: {'locale': _locale},
      );
      return _parseCategory(data);
    } catch (error) {
      if (error is NowaveApiException && error.statusCode == 404) return null;
      throw mapToServerException(error);
    }
  }

  @override
  Future<List<BlogModel>> getArticlesByCategory(
    String slug, {
    required int offset,
  }) async {
    final wanted = slug.trim();
    if (!_isUsableSlug(wanted) || offset < 0) {
      throw const ServerException(
        '分类标识无效',
        kind: FailureKind.validation,
        code: 'client.validation',
      );
    }
    try {
      final data = await _client.getJson(
        '/categories/${Uri.encodeComponent(wanted)}/articles',
        query: {
          'limit': '$kCategoryPageSize',
          'offset': '$offset',
          'locale': _locale,
        },
      );
      return articlePayloadList(data);
    } catch (error) {
      if (error is NowaveApiException && error.statusCode == 404) {
        // The category vanished between reading its name and its articles.
        throw _categoryNotFound;
      }
      throw mapToServerException(error);
    }
  }

  /// One taxonomy row: `{id, kind, slug, name, description, locale}`. `id`,
  /// `kind` and `locale` are not kept - the slug is the address and the name is
  /// what the reader sees.
  CategoryRef _parseCategory(dynamic value) {
    if (value is! Map<String, dynamic>) throw _invalidResponse;
    final slug = value['slug'];
    final name = value['name'];
    final description = value['description'];
    if (slug is! String ||
        !_isUsableSlug(slug) ||
        name is! String ||
        name.trim().isEmpty ||
        (description != null && description is! String)) {
      throw _invalidResponse;
    }
    return CategoryRef(
      slug: slug,
      name: name.trim(),
      description: (description as String? ?? '').trim(),
    );
  }
}
