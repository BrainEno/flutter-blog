import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/user/data/datasources/author_relationship_remote_data_source.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _ok(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _profile(String id) => {
  'userId': id,
  'displayName': 'Writer $id',
  'bio': 'A public bio',
  'avatarUrl': 'https://images.example.invalid/a.webp',
  'isFollowing': true,
  'role': 'editor',
};

void main() {
  test(
    'both lists use public GET, encode opaque IDs and never send credentials',
    () async {
      const userId = 'writer/name?ref=1#%中';
      final seen = <http.Request>[];
      final remote = AuthorRelationshipRemoteDataSourceImpl(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((request) async {
          seen.add(request);
          return _ok([_profile('reader-1')]);
        }),
      );
      for (final kind in AuthorRelationshipKind.values) {
        final people = await remote.getRelationships(
          userId: userId,
          kind: kind,
        );
        expect(people, hasLength(1));
        expect(people.single.userId, 'reader-1');
        expect(people.single.displayName, 'Writer reader-1');
        expect(people.single.bio, 'A public bio');
        expect(
          people.single.avatarUrl,
          'https://images.example.invalid/a.webp',
        );
        expect(() => people.clear(), throwsUnsupportedError);
      }
      expect(seen, hasLength(2));
      for (var i = 0; i < seen.length; i++) {
        final request = seen[i];
        expect(request.method, 'GET');
        expect(request.url.pathSegments, [
          'api',
          'v1',
          'users',
          userId,
          AuthorRelationshipKind.values[i].name,
        ]);
        expect(request.url.queryParameters, {
          'locale': 'zh-CN',
          'limit': '100',
        });
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
      }
    },
  );

  test('empty and nullable public profile fields stay empty', () async {
    final remote = AuthorRelationshipRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient(
        (_) async => _ok([
          {
            'userId': 'reader',
            'displayName': null,
            'bio': null,
            'avatarUrl': null,
          },
        ]),
      ),
    );
    final people = await remote.getRelationships(
      userId: 'author',
      kind: AuthorRelationshipKind.following,
    );
    expect(people.single.displayName, isEmpty);
    expect(people.single.bio, isEmpty);
    expect(people.single.avatarUrl, isEmpty);
  });

  test('invalid target IDs fail before any request', () async {
    var calls = 0;
    final remote = AuthorRelationshipRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient((_) async {
        calls++;
        return _ok([]);
      }),
    );
    for (final id in ['', ' author', 'author ', '.', '..', 'a' * 301]) {
      await expectLater(
        remote.getRelationships(
          userId: id,
          kind: AuthorRelationshipKind.followers,
        ),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', 'server.parse'),
        ),
      );
    }
    expect(calls, 0);
  });

  test(
    'oversized, duplicate or malformed rows are not treated as a valid list',
    () async {
      final badPayloads = <Object?>[
        null,
        {'userId': 'not-a-list'},
        [42],
        [{}],
        [
          {'userId': '.'},
        ],
        [
          {'userId': 'ok', 'displayName': 42},
        ],
        [
          {'userId': 'ok', 'bio': false},
        ],
        [
          {'userId': 'ok', 'avatarUrl': []},
        ],
        [_profile('duplicate'), _profile('duplicate')],
        List.generate(101, (i) => _profile('reader-$i')),
      ];
      for (final bad in badPayloads) {
        final remote = AuthorRelationshipRemoteDataSourceImpl(
          baseUrl: Uri.parse('https://api.example.invalid'),
          httpClient: MockClient((_) async => _ok(bad)),
        );
        await expectLater(
          remote.getRelationships(
            userId: 'author',
            kind: AuthorRelationshipKind.followers,
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'code',
              'server.parse',
            ),
          ),
        );
      }
    },
  );

  test('HTTP errors remain failures and do not expose server text', () async {
    final remote = AuthorRelationshipRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'RATE_LIMITED', 'message': 'raw detail'},
          }),
          429,
        ),
      ),
    );
    await expectLater(
      remote.getRelationships(
        userId: 'author',
        kind: AuthorRelationshipKind.followers,
      ),
      throwsA(
        isA<ServerException>()
            .having((e) => e.code, 'code', 'server.RATE_LIMITED')
            .having((e) => e.message, 'message', isNot(contains('raw detail'))),
      ),
    );
  });
}
