import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class MockSessionManager extends Mock implements NowaveSessionManager {}

NowaveApiClient _client(http.Client inner) => NowaveApiClient(
  baseUrl: Uri.parse('https://api.example.invalid'),
  httpClient: inner,
);

UserRemoteDataSourceImpl _dataSource(http.Client inner) =>
    UserRemoteDataSourceImpl(_client(inner), MockSessionManager());

/// A client that records every request and always answers with [response].
MockClient _recorder(
  List<http.Request> requests,
  http.Response response,
) => MockClient((request) async {
  requests.add(request);
  return response;
});

/// The `PUT /me/profile` reply: the stored profile read back.
http.Response _profileResponse({
  String bio = '写诗的人',
  String? avatarUrl,
  String? websiteUrl,
}) => http.Response(
  jsonEncode({
    'data': {
      'userId': 'u1',
      'displayName': '新名字',
      'bio': bio,
      'avatarUrl': avatarUrl,
      'websiteUrl': websiteUrl,
      'updatedAt': '2025-01-01T00:00:00.000Z',
    },
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

UserModel _user({
  String bio = '写诗的人',
  String website = '',
  String avatarUrl = '',
}) => UserModel(
  id: 'u1',
  email: 'a@example.invalid',
  name: '新名字',
  bio: bio,
  website: website,
  avatarUrl: avatarUrl,
  updatedAt: DateTime.utc(2024),
);

Map<String, dynamic> _bodyOf(http.Request request) =>
    jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;

void main() {
  test('the write body always carries the bio, even when unchanged', () async {
    final requests = <http.Request>[];
    final source = _dataSource(_recorder(requests, _profileResponse()));

    final saved = await source.editUserInfo(_user(bio: '写诗的人'));

    expect(requests, hasLength(1));
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v1/me/profile');
    final body = _bodyOf(requests.single);
    // A missing `bio` is stored as '' by the backend, which used to erase the
    // introduction of every author who edited any other field.
    expect(body['displayName'], '新名字');
    expect(body['bio'], '写诗的人');
    expect(body.containsKey('avatarUrl'), isFalse);
    // '' is rejected for a URL field: clearing it needs an explicit null.
    expect(body['websiteUrl'], isNull);
    expect(saved.bio, '写诗的人');
  });

  test('an empty bio is sent as an empty string, not omitted', () async {
    final requests = <http.Request>[];
    final source = _dataSource(_recorder(requests, _profileResponse(bio: '')));

    await source.editUserInfo(_user(bio: ''));

    final body = _bodyOf(requests.single);
    expect(body.containsKey('bio'), isTrue);
    expect(body['bio'], '');
  });

  test('a website is trimmed, and the avatar is sent when present', () async {
    final requests = <http.Request>[];
    final source = _dataSource(
      _recorder(
        requests,
        _profileResponse(
          avatarUrl: 'https://api.example.invalid/api/v1/media/a',
          websiteUrl: 'https://example.invalid',
        ),
      ),
    );

    final saved = await source.editUserInfo(
      _user(
        website: ' https://example.invalid ',
        avatarUrl: 'https://cdn.invalid/a.webp',
      ),
    );

    final body = _bodyOf(requests.single);
    expect(body['websiteUrl'], 'https://example.invalid');
    expect(body['avatarUrl'], 'https://cdn.invalid/a.webp');
    expect(saved.website, 'https://example.invalid');
  });

  test('a profile reply without a bio maps to an empty bio', () async {
    final requests = <http.Request>[];
    final source = _dataSource(
      _recorder(
        requests,
        http.Response(
          jsonEncode({
            'data': {
              'userId': 'u1',
              'displayName': '新名字',
              'avatarUrl': null,
              'websiteUrl': null,
              'updatedAt': '2025-01-01T00:00:00.000Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final saved = await source.editUserInfo(_user());

    expect(saved.bio, '');
    expect(saved.website, '');
    expect(saved.name, '新名字');
  });
}
