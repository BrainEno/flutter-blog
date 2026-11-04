import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:http/http.dart' as http;

abstract interface class AuthorSearchRemoteDataSource {
  Future<List<AuthorSearchResult>> search(String query);
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

  @override
  Future<List<AuthorSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (!isValidAuthorSearchQuery(trimmed)) throw _invalidQuery;
    try {
      final data = await _client.getJson(
        '/users',
        query: {
          'query': trimmed,
          'locale': _locale,
          'limit': '$maxAuthorSearchResults',
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
        final avatar = value['avatarUrl'];
        if (id is! String ||
            !_isUsableUserId(id) ||
            !seen.add(id) ||
            (name != null && name is! String) ||
            (bio != null && bio is! String) ||
            (avatar != null && avatar is! String)) {
          throw _invalidResponse;
        }
        // The API may return isFollowing, role and other fields; none are
        // needed for an anonymous search or stored in this entity.
        people.add(
          AuthorSearchResult(
            userId: id,
            displayName: name as String? ?? '',
            bio: bio as String? ?? '',
            avatarUrl: avatar as String? ?? '',
          ),
        );
      }
      return List.unmodifiable(people);
    } catch (error) {
      throw mapToServerException(error);
    }
  }
}
