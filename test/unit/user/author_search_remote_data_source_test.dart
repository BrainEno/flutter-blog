import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/user/data/datasources/author_search_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _ok(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _profile(String id, {int followers = 3, int works = 2}) =>
    {
      'userId': id,
      'displayName': 'Writer $id',
      'bio': 'Public biography',
      'locale': 'zh-CN',
      'followerCount': followers,
      'workCount': works,
      'isFollowing': true,
      'role': 'editor',
    };

TypeMatcher<ServerException> _parseError() => isA<ServerException>().having(
  (error) => error.code,
  'code',
  'server.parse',
);

void main() {
  test('search encodes the trimmed query and sends no credentials', () async {
    const query = '林 +/&?=%🌊';
    final seen = <http.Request>[];
    final remote = AuthorSearchRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid/prefix'),
      httpClient: MockClient((request) async {
        seen.add(request);
        return _ok([_profile('writer/name', followers: 7, works: 11)]);
      }),
    );
    final people = await remote.search('  $query  ');
    expect(seen, hasLength(1));
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/prefix/api/v1/authors');
    expect(seen.single.url.queryParameters, {
      'query': query,
      'locale': 'zh-CN',
      'limit': '100',
    });
    expect(seen.single.headers.containsKey('authorization'), isFalse);
    expect(seen.single.headers.containsKey('cookie'), isFalse);
    expect(people.single.userId, 'writer/name');
    expect(people.single.displayName, 'Writer writer/name');
    expect(people.single.bio, 'Public biography');
    expect(people.single.followerCount, 7);
    expect(people.single.workCount, 11);
    expect(() => people.clear(), throwsUnsupportedError);
  });

  test('the directory sends no query parameter at all', () async {
    final seen = <http.Request>[];
    final remote = AuthorSearchRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient((request) async {
        seen.add(request);
        return _ok([_profile('one'), _profile('two')]);
      }),
    );
    final people = await remote.directory();
    expect(seen.single.url.path, '/api/v1/authors');
    expect(seen.single.url.queryParameters, {
      'locale': 'zh-CN',
      'limit': '100',
    });
    expect(people.map((person) => person.userId), ['one', 'two']);
  });

  test('empty or oversized UTF-16 queries never make a request', () async {
    var calls = 0;
    final remote = AuthorSearchRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: MockClient((_) async {
        calls++;
        return _ok([]);
      }),
    );
    for (final input in ['', '   ', 'x' * 101, '🌊' * 51]) {
      await expectLater(
        remote.search(input),
        throwsA(
          isA<ServerException>().having(
            (error) => error.code,
            'code',
            'client.validation',
          ),
        ),
      );
    }
    expect(calls, 0);
    await remote.search('🌊' * 50);
    expect(calls, 1);
  });

  test(
    'nullable fields, absent counters and 100 valid rows are accepted',
    () async {
      final remote = AuthorSearchRemoteDataSourceImpl(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient(
          (_) async => _ok([
            {'userId': 'one', 'displayName': null, 'bio': null},
            for (var i = 1; i < 100; i++) _profile('writer-$i'),
          ]),
        ),
      );
      final people = await remote.search('one');
      expect(people, hasLength(100));
      expect(people.first.displayName, isEmpty);
      expect(people.first.bio, isEmpty);
      // A row that predates the counters is a row with nothing to show, not a
      // broken row.
      expect(people.first.followerCount, 0);
      expect(people.first.workCount, 0);
    },
  );

  test('invalid, duplicate and oversized responses fail closed', () async {
    final badPayloads = <Object?>[
      null,
      {'userId': 'not-a-list'},
      [42],
      [{}],
      [
        {'userId': ''},
      ],
      [
        {'userId': ' x'},
      ],
      [
        {'userId': '.'},
      ],
      [
        {'userId': '..'},
      ],
      [
        {'userId': 'x' * 301},
      ],
      [
        {'userId': 'x', 'displayName': 42},
      ],
      [
        {'userId': 'x', 'bio': false},
      ],
      [
        {'userId': 'x', 'followerCount': -1},
      ],
      [
        {'userId': 'x', 'followerCount': '12'},
      ],
      [
        {'userId': 'x', 'workCount': 1.5},
      ],
      [_profile('same'), _profile('same')],
      List.generate(101, (i) => _profile('writer-$i')),
    ];
    for (final bad in badPayloads) {
      final remote = AuthorSearchRemoteDataSourceImpl(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((_) async => _ok(bad)),
      );
      await expectLater(remote.search('query'), throwsA(_parseError()));
      await expectLater(remote.directory(), throwsA(_parseError()));
    }
  });

  test('HTTP failures do not expose server messages as display text', () async {
    final remote = AuthorSearchRemoteDataSourceImpl(
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
      remote.search('query'),
      throwsA(
        isA<ServerException>()
            .having((error) => error.code, 'code', 'server.RATE_LIMITED')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('raw detail')),
            ),
      ),
    );
  });
}
