import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNowaveApiClient extends Mock implements NowaveApiClient {}

class MockSessionManager extends Mock implements NowaveSessionManager {}

Map<String, dynamic> _profile({String bio = '既有简介'}) => <String, dynamic>{
  'userId': 'u1',
  'displayName': '新名字',
  'bio': bio,
  'avatarUrl': 'https://api.example.invalid/api/v1/media/avatar',
  'websiteUrl': 'https://example.invalid',
  'updatedAt': '2025-01-01T00:00:00.000Z',
};

void main() {
  late MockNowaveApiClient client;
  late MockSessionManager sessionManager;
  late UserRemoteDataSourceImpl dataSource;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = MockNowaveApiClient();
    sessionManager = MockSessionManager();
    when(() => sessionManager.currentSession).thenReturn(null);
    dataSource = UserRemoteDataSourceImpl(client, sessionManager);
  });

  group('editUserInfo', () {
    test('writes bio and websiteUrl as distinct profile fields', () async {
      when(
        () => client.putJson(any(), any()),
      ).thenAnswer((_) async => _profile());

      final result = await dataSource.editUserInfo(
        UserModel(
          id: 'u1',
          email: 'user@example.invalid',
          name: '新名字',
          avatarUrl: 'https://api.example.invalid/api/v1/media/avatar',
          bio: '既有简介',
          website: 'https://example.invalid',
          updatedAt: DateTime.utc(2024),
        ),
      );

      verify(
        () => client.putJson('/me/profile', <String, dynamic>{
          'displayName': '新名字',
          'bio': '既有简介',
          'avatarUrl': 'https://api.example.invalid/api/v1/media/avatar',
          'websiteUrl': 'https://example.invalid',
        }),
      ).called(1);
      expect(result.bio, '既有简介');
      expect(result.website, 'https://example.invalid');
      expect(result.email, 'user@example.invalid');
    });

    test('empty URLs stay omitted and never turn into an empty bio', () async {
      when(
        () => client.putJson(any(), any()),
      ).thenAnswer((_) async => _profile());

      await dataSource.editUserInfo(
        UserModel(
          id: 'u1',
          email: 'user@example.invalid',
          name: '新名字',
          bio: '既有简介',
          updatedAt: DateTime.utc(2024),
        ),
      );

      verify(
        () => client.putJson('/me/profile', <String, dynamic>{
          'displayName': '新名字',
          'bio': '既有简介',
        }),
      ).called(1);
    });

    test('an invalid profile response remains a typed server error', () async {
      when(
        () => client.putJson(any(), any()),
      ).thenAnswer((_) async => <dynamic>[]);

      await expectLater(
        () => dataSource.editUserInfo(
          UserModel(
            id: 'u1',
            email: 'user@example.invalid',
            name: '新名字',
            bio: '既有简介',
            updatedAt: DateTime.utc(2024),
          ),
        ),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
