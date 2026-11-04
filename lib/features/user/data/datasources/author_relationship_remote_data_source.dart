import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:http/http.dart' as http;

abstract interface class AuthorRelationshipRemoteDataSource {
  Future<List<AuthorRelationship>> getRelationships({
    required String userId,
    required AuthorRelationshipKind kind,
  });
}

/// A dedicated anonymous client: the public endpoint does not need the
/// viewer-resolved `isFollowing` field, so it never receives a session token
/// or triggers token refresh. The list itself is not cached or persisted.
class AuthorRelationshipRemoteDataSourceImpl
    implements AuthorRelationshipRemoteDataSource {
  AuthorRelationshipRemoteDataSourceImpl({
    required Uri baseUrl,
    http.Client? httpClient,
    this.contentLocale,
  }) : _client = NowaveApiClient(baseUrl: baseUrl, httpClient: httpClient);

  /// Content language for the requests this data source makes; null keeps the
  /// historical Chinese default for callers that never switch (tests).
  final ContentLocale? contentLocale;

  String get _locale => (contentLocale ?? ContentLocale.instance).tag;

  final NowaveApiClient _client;

  static bool _isUsableUserId(String value) =>
      value.isNotEmpty &&
      value.length <= 300 &&
      value == value.trim() &&
      // Dot segments are normalized out by URI stacks before the REST router
      // sees them; fail closed instead of addressing a different endpoint.
      value != '.' &&
      value != '..';

  static const _invalidResponse = ServerException(
    '服务器返回了无法解析的数据',
    code: 'server.parse',
  );

  @override
  Future<List<AuthorRelationship>> getRelationships({
    required String userId,
    required AuthorRelationshipKind kind,
  }) async {
    if (!_isUsableUserId(userId)) throw _invalidResponse;
    try {
      // The ID is one opaque path segment, not a path or query string. Dart's
      // URI builder preserves escaped reserved characters such as %2F.
      final encodedUserId = Uri.encodeComponent(userId);
      final data = await _client.getJson(
        '/users/$encodedUserId/${kind.name}',
        query: {'locale': _locale, 'limit': '$maxAuthorRelationshipResults'},
      );
      if (data is! List || data.length > maxAuthorRelationshipResults) {
        throw _invalidResponse;
      }
      final seen = <String>{};
      final profiles = <AuthorRelationship>[];
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
        profiles.add(
          AuthorRelationship(
            userId: id,
            displayName: name as String? ?? '',
            bio: bio as String? ?? '',
            avatarUrl: avatar as String? ?? '',
          ),
        );
      }
      return List.unmodifiable(profiles);
    } catch (error) {
      throw mapToServerException(error);
    }
  }
}
