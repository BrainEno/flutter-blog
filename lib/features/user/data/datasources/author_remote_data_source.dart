import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/user/data/models/author_profile_model.dart';

/// Public author profiles and the follow relationship (issue #20).
///
/// The follow endpoints return the target's fresh profile after the
/// write, so the follow state always comes back server-resolved — a
/// duplicate follow or unfollow is a no-op server-side, never an error
/// and never a second notification.
abstract interface class AuthorRemoteDataSource {
  Future<AuthorProfileModel> getAuthorProfile(String userId);

  Future<AuthorProfileModel> followAuthor(String userId);

  Future<AuthorProfileModel> unfollowAuthor(String userId);
}

class AuthorRemoteDataSourceImpl implements AuthorRemoteDataSource {
  final NowaveApiClient client;
  const AuthorRemoteDataSourceImpl(this.client);

  @override
  Future<AuthorProfileModel> getAuthorProfile(String userId) async {
    try {
      final data = await client.getJson(
        '/authors/$userId',
        query: {'locale': 'zh-CN'},
      );
      return _profile(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<AuthorProfileModel> followAuthor(String userId) async {
    try {
      final data = await client.postJson(
        '/users/$userId/follow',
        null,
        query: {'locale': 'zh-CN'},
      );
      return _profile(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<AuthorProfileModel> unfollowAuthor(String userId) async {
    try {
      // No query: the server's locale parser defaults to zh-CN, and the
      // client's URI builder percent-encodes a '?' embedded in the path.
      final data = await client.deleteJson('/users/$userId/follow');
      return _profile(data);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  AuthorProfileModel _profile(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const ServerException('服务器返回了无法解析的数据', code: 'server.parse');
    }
    return AuthorProfileModel.fromMap(data);
  }
}
