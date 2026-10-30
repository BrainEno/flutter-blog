import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNowaveApiClient extends Mock implements NowaveApiClient {}

const _kUserId = 'author-1';

/// An author profile row as the server serializes it.
Map<String, dynamic> _profileMap({bool isFollowing = false}) {
  return <String, dynamic>{
    'userId': _kUserId,
    'displayName': '作者甲',
    'bio': '写点东西',
    'avatarUrl': 'https://img.example.invalid/a.png',
    'websiteUrl': 'https://example.invalid',
    'locale': 'zh-CN',
    'followerCount': 12,
    'followingCount': 3,
    'isFollowing': isFollowing,
    'createdAt': '2025-01-01T00:00:00.000Z',
    'updatedAt': '2025-06-01T00:00:00.000Z',
  };
}

void main() {
  late MockNowaveApiClient client;
  late AuthorRemoteDataSourceImpl dataSource;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = MockNowaveApiClient();
    dataSource = AuthorRemoteDataSourceImpl(client);
  });

  group('getAuthorProfile', () {
    test(
      'maps the profile row with the viewer-resolved follow state',
      () async {
      when(
        () => client.getJson(any(), query: any(named: 'query')),
      ).thenAnswer((_) async => _profileMap(isFollowing: true));

      final profile = await dataSource.getAuthorProfile(_kUserId);

      expect(profile.userId, _kUserId);
      expect(profile.displayName, '作者甲');
      expect(profile.bio, '写点东西');
      expect(profile.websiteUrl, 'https://example.invalid');
      expect(profile.followerCount, 12);
      expect(profile.followingCount, 3);
      expect(profile.isFollowing, isTrue);
      verify(
        () => client.getJson(
          '/authors/$_kUserId',
          query: {'locale': 'zh-CN'},
        ),
      ).called(1);
    });

    test('an API error surfaces as a ServerException', () async {
      when(() => client.getJson(any(), query: any(named: 'query'))).thenThrow(
        NowaveApiException(statusCode: 404, code: 'NOT_FOUND', message: 'gone'),
      );

      expect(
        () => dataSource.getAuthorProfile(_kUserId),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('followAuthor', () {
    test('posts and maps the fresh profile the server returns', () async {
      when(
        () => client.postJson(any(), any(), query: any(named: 'query')),
      ).thenAnswer((_) async => _profileMap(isFollowing: true));

      final profile = await dataSource.followAuthor(_kUserId);

      expect(profile.isFollowing, isTrue);
      expect(profile.followerCount, 12);
      verify(
        () => client.postJson(
          '/users/$_kUserId/follow',
          null,
          query: {'locale': 'zh-CN'},
        ),
      ).called(1);
    });
  });

  group('unfollowAuthor', () {
    test('deletes without a query and maps the fresh profile', () async {
      when(
        () => client.deleteJson(any()),
      ).thenAnswer((_) async => _profileMap(isFollowing: false));

      final profile = await dataSource.unfollowAuthor(_kUserId);

      expect(profile.isFollowing, isFalse);
      verify(() => client.deleteJson('/users/$_kUserId/follow')).called(1);
    });
  });
}
