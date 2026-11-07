import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:http/http.dart' as http;

/// The public author directory (ADR 0024). `search` narrows it by name; an
/// empty query browses it, ordered by reach. The directory has no cursor, so a
/// deeper page is named by the number of rows already read.
abstract interface class AuthorSearchRemoteDataSource {
  Future<List<AuthorSearchResult>> search(String query, {int offset = 0});
  Future<List<AuthorSearchResult>> directory({int offset = 0});
}

/// The endpoint is public. Its dedicated client cannot send a session token
/// or trigger a refresh, even when the rest of the app is signed in.
class AuthorSearchRemoteDataSourceImpl implements AuthorSearchRemoteDataSource {
  AuthorSearchRemoteDataSourceImpl({
    required Uri baseUrl,
    http.Client? httpClient,
    this.contentLocale,
  }) : _client = NowaveApiClient(baseUrl: baseUrl, httpClient: httpClient);

  /// Content language for the requests this data source makes; null keeps the
  /// historical Chinese default for callers that never switch (tests).
  ///
  /// The directory only lists authors who have a published work in this
  /// language, so the language is part of the answer, not a display setting.
  final ContentLocale? contentLocale;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  final NowaveApiClient _client;

  static const _invalidResponse = ServerException(
    '服务器返回了无法解析的数据',
    code: 'server.parse',
  );
  static const _invalidQuery = ServerException(
    '搜索关键词不符合要求',
    code: 'client.validation',
    kind: FailureKind.validation,
  );

  // IDs are opaque path segments, but a dot segment can be normalized away
  // by a URI stack before the author's route is reached.
  static bool _isUsableUserId(String value) =>
      value.isNotEmpty &&
      value.length <= 300 &&
      value == value.trim() &&
      value != '.' &&
      value != '..';

  /// A counter is a non-negative integer that fits a page header. Anything else
  /// - a float, a string, a negative - means the row is not what it claims.
  static int? _asCount(Object? value) {
    if (value == null) return 0;
    if (value is! int || value < 0) return null;
    return value;
  }

  @override
  Future<List<AuthorSearchResult>> search(String query, {int offset = 0}) {
    final trimmed = query.trim();
    if (!isValidAuthorSearchQuery(trimmed) || !_isUsableOffset(offset)) {
      return Future.error(_invalidQuery);
    }
    return _fetch(query: trimmed, offset: offset);
  }

  /// The browse case: no query parameter at all, so the server orders the
  /// directory by reach instead of by relevance.
  @override
  Future<List<AuthorSearchResult>> directory({int offset = 0}) {
    if (!_isUsableOffset(offset)) return Future.error(_invalidQuery);
    return _fetch(offset: offset);
  }

  /// The first page sends no `offset` at all, so an older deployment that
  /// ignores the parameter still answers with the list it always did.
  static bool _isUsableOffset(int offset) =>
      offset >= 0 && offset <= maxAuthorSearchOffset;

  Future<List<AuthorSearchResult>> _fetch({
    String? query,
    int offset = 0,
  }) async {
    try {
      final data = await _client.getJson(
        '/authors',
        query: {
          if (query != null) 'query': query,
          'locale': _locale,
          'limit': '$maxAuthorSearchResults',
          if (offset > 0) 'offset': '$offset',
        },
      );
      if (data is! List || data.length > maxAuthorSearchResults) {
        throw _invalidResponse;
      }
      final seen = <String>{};
      final people = <AuthorSearchResult>[];
      for (final value in data) {
        if (value is! Map<String, dynamic>) throw _invalidResponse;
        final id = value['userId'];
        final name = value['displayName'];
        final bio = value['bio'];
        final followers = _asCount(value['followerCount']);
        final works = _asCount(value['workCount']);
        if (id is! String ||
            !_isUsableUserId(id) ||
            !seen.add(id) ||
            (name != null && name is! String) ||
            (bio != null && bio is! String) ||
            followers == null ||
            works == null) {
          throw _invalidResponse;
        }
        // The directory deliberately carries no avatar, no role and no follow
        // state: those depend on the reader, and this response does not. Any
        // extra fields are ignored rather than stored.
        people.add(
          AuthorSearchResult(
            userId: id,
            displayName: name as String? ?? '',
            bio: bio as String? ?? '',
            followerCount: followers,
            workCount: works,
          ),
        );
      }
      return List.unmodifiable(people);
    } catch (error) {
      throw mapToServerException(error);
    }
  }
}
