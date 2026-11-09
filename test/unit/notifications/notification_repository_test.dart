import 'dart:convert';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/entities/notification_page.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator {
  String? user = 'user-a';
  String? token = 'fake-token-a';
  int generation = 1;
  int refreshCount = 0;

  @override
  String? get accessToken => token;

  @override
  String? get activeUserId => user;

  @override
  int get sessionGeneration => generation;

  @override
  Future<bool> refresh() async {
    refreshCount++;
    return false;
  }

  void replace() {
    generation++;
    user = 'user-b';
    token = 'fake-token-b';
  }
}

const _fence = NowaveSessionFence(userId: 'user-a', generation: 1);

NotificationRepositoryImpl _repository(_Auth auth, MockClient httpClient) =>
    NotificationRepositoryImpl(
      NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        authenticator: auth,
        httpClient: httpClient,
      ),
    );

Map<String, dynamic> _row({
  String id = 'notification-1',
  Map<String, Object?> payload = const {
    'type': 'message.created',
    'messageId': 'message-1',
    'conversationId': 'conversation-1',
    'senderId': 'user-b',
  },
  String? readAt,
}) => {
  'id': id,
  'eventKey': 'message.created:message-1:user-a',
  'payload': jsonEncode(payload),
  'createdAt': '2026-11-05T04:30:00.000Z',
  'readAt': readAt,
};

http.Response _data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

Failure? _failure(Either<Failure, Object?> result) =>
    result.fold((failure) => failure, (_) => null);

void main() {
  test('reads the inbox with a bounded limit and no redirects', () async {
    final auth = _Auth();
    final seen = <http.Request>[];
    final repository = _repository(
      auth,
      MockClient((request) async {
        seen.add(request);
        return _data([
          _row(id: '11111111-1111-4111-8111-111111111111'),
          _row(
            id: '22222222-2222-4222-8222-222222222222',
            payload: const {
              'type': 'article.deleted',
              'articleId': 'article-9',
              'purgesAt': '2026-12-05T00:00:00.000Z',
            },
          ),
        ]);
      }),
    );

    final result = await repository.list(fence: _fence);
    final page = result.fold<NotificationPage?>((_) => null, (value) => value)!;
    final items = page.items;

    expect(seen, hasLength(1));
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/v1/me/notifications');
    expect(seen.single.url.queryParameters['limit'], '50');
    expect(seen.single.followRedirects, isFalse);
    expect(seen.single.headers['authorization'], 'Bearer fake-token-a');
    expect(items.map((item) => item.id), [
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
    ]);
    expect(items.first.kind, AppNotificationKind.messageReceived);
    expect(items.last.kind, AppNotificationKind.articleDeleted);
    expect(
      utf8.decode(base64Url.decode(base64Url.normalize(page.nextCursor!))),
      '2026-11-05T04:30:00.000Z|22222222-2222-4222-8222-222222222222',
    );
    expect(page.nextCursor, isNot(contains('=')));
    expect(() => items.clear(), throwsUnsupportedError);
  });

  test(
    'sends the exact continuation cursor with the bounded page size',
    () async {
      final expectedCursor = base64Url
          .encode(
            utf8.encode(
              '2026-11-05T04:29:00.000Z|aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            ),
          )
          .replaceAll('=', '');
      final seen = <http.Request>[];
      final repository = _repository(
        _Auth(),
        MockClient((request) async {
          seen.add(request);
          return _data([_row(id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')]);
        }),
      );

      final result = await repository.list(
        fence: _fence,
        limit: 20,
        cursor: expectedCursor,
      );

      expect(_failure(result), isNull);
      expect(seen.single.url.queryParameters['limit'], '20');
      expect(seen.single.url.queryParameters['cursor'], expectedCursor);
      expect(seen.single.url.queryParameters.containsKey('offset'), isFalse);
    },
  );

  test('keeps a request below the server maximum', () async {
    final limits = <String?>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        limits.add(request.url.queryParameters['limit']);
        return _data(const []);
      }),
    );

    await repository.list(fence: _fence, limit: 1000);
    await repository.list(fence: _fence, limit: 0);
    await repository.list(fence: _fence, limit: 100);

    expect(limits, ['100', '1', '100']);
  });

  test('accepts an empty inbox', () async {
    final repository = _repository(_Auth(), MockClient((_) async => _data([])));

    final result = await repository.list(fence: _fence);

    final page = result.fold<NotificationPage?>((_) => null, (value) => value)!;

    expect(page.items, isEmpty);
    expect(page.nextCursor, isNull);
  });

  for (final entry in <int, String>{
    401: 'server.UNAUTHENTICATED',
    404: 'notifications.unavailable',
    405: 'notifications.unavailable',
    429: 'server.RATE_LIMITED',
    500: 'server.error',
  }.entries) {
    test('HTTP ${entry.key} is classified without exposing its body', () async {
      final repository = _repository(
        _Auth(),
        MockClient(
          (_) async => http.Response('private server message', entry.key),
        ),
      );

      final failure = _failure(await repository.list(fence: _fence));

      expect(failure?.code, entry.value);
      expect(failure?.message, isNot(contains('private server message')));
      expect(failure?.cause, isNull);
    });
  }

  group('a success response this build cannot read is a parse failure', () {
    final responses = <String, http.Response>{
      'a non-list payload': _data({'notifications': []}),
      'a row that is not an object': _data(['notification-1']),
      'a row without a created time': _data([_row()..remove('createdAt')]),
      'a body that is not JSON': http.Response('not json', 200),
    };

    for (final entry in responses.entries) {
      test(entry.key, () async {
        final repository = _repository(
          _Auth(),
          MockClient((_) async => entry.value),
        );

        final failure = _failure(await repository.list(fence: _fence));

        expect(failure?.code, 'client.parse');
      });
    }
  });

  test('rejects rows that cannot form a backend cursor', () async {
    final invalidResponses = <Object?>[
      [
        {..._row(), 'id': 'not-a-uuid'},
      ],
      [
        {
          ..._row(id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
          'createdAt': '2026-11-05T04:30:00Z',
        },
      ],
    ];

    for (final response in invalidResponses) {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => _data(response)),
      );

      expect(
        _failure(await repository.list(fence: _fence))?.code,
        'client.parse',
      );
    }
  });

  test(
    'a cursor-only 400 is reported as an unsupported continuation',
    () async {
      final repository = _repository(
        _Auth(),
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'BAD_USER_INPUT',
                'message': 'Invalid cursor query parameter.',
              },
            }),
            400,
          ),
        ),
      );

      final failure = _failure(
        await repository.list(fence: _fence, cursor: 'a-valid-looking-cursor'),
      );

      expect(failure?.code, notificationCursorUnavailableFailureCode);
    },
  );

  test('a replaced account cannot read the old inbox', () async {
    final auth = _Auth();
    var requests = 0;
    final repository = _repository(
      auth,
      MockClient((_) async {
        requests++;
        return _data(const []);
      }),
    );
    auth.replace();

    final failure = _failure(await repository.list(fence: _fence));

    expect(requests, 0);
    expect(failure?.code, 'auth.sessionChanged');
  });

  group('unread count', () {
    test('asks the dedicated endpoint and returns the number', () async {
      final seen = <http.Request>[];
      final repository = _repository(
        _Auth(),
        MockClient((request) async {
          seen.add(request);
          return _data(3);
        }),
      );

      final result = await repository.unreadCount(fence: _fence);

      expect(result.fold((_) => null, (count) => count), 3);
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/me/notifications/unread-count');
      expect(seen.single.url.query, isEmpty);
      expect(seen.single.headers['authorization'], 'Bearer fake-token-a');
    });

    test('an empty inbox is zero', () async {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => _data(0)),
      );

      final result = await repository.unreadCount(fence: _fence);

      expect(result.fold((_) => null, (count) => count), 0);
    });

    for (final entry in <String, http.Response>{
      'a negative count': _data(-1),
      'a count that is a string': _data('3'),
      'a count that is an object': _data({'count': 3}),
      'a body that is not JSON': http.Response('not json', 200),
    }.entries) {
      test('${entry.key} is a parse failure', () async {
        final repository = _repository(
          _Auth(),
          MockClient((_) async => entry.value),
        );

        final failure = _failure(await repository.unreadCount(fence: _fence));

        expect(failure?.code, 'client.parse');
      });
    }

    test('an older deployment answers 404: unavailable, not zero', () async {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => http.Response('missing', 404)),
      );

      final failure = _failure(await repository.unreadCount(fence: _fence));

      expect(failure?.code, 'notifications.unavailable');
    });

    test('a replaced account cannot read the old count', () async {
      final auth = _Auth();
      var requests = 0;
      final repository = _repository(
        auth,
        MockClient((_) async {
          requests++;
          return _data(7);
        }),
      );
      auth.replace();

      final failure = _failure(await repository.unreadCount(fence: _fence));

      expect(requests, 0);
      expect(failure?.code, 'auth.sessionChanged');
    });
  });

  test('marks one notification read with an empty body', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data(_row(readAt: '2026-11-05T06:00:00.000Z'));
      }),
    );

    final result = await repository.markRead('notification-1', fence: _fence);
    final updated = result.fold<AppNotification?>((_) => null, (v) => v)!;

    expect(seen.single.method, 'PUT');
    expect(
      seen.single.url.path,
      '/api/v1/me/notifications/notification-1/read',
    );
    expect(seen.single.body, isEmpty);
    expect(seen.single.headers['content-type'], isNull);
    expect(updated.isRead, isTrue);
    expect(updated.readAt, DateTime.utc(2026, 11, 5, 6));
  });

  test('a repeated mark read is accepted, not rejected', () async {
    final repository = _repository(
      _Auth(),
      MockClient((_) async => _data(_row(readAt: '2026-11-05T06:00:00.000Z'))),
    );

    final first = await repository.markRead('notification-1', fence: _fence);
    final second = await repository.markRead('notification-1', fence: _fence);

    expect(_failure(first), isNull);
    expect(_failure(second), isNull);
  });

  test('rejects an empty notification id without a request', () async {
    var requests = 0;
    final repository = _repository(
      _Auth(),
      MockClient((_) async {
        requests++;
        return _data(_row());
      }),
    );

    final failure = _failure(await repository.markRead('', fence: _fence));

    expect(requests, 0);
    expect(failure?.code, 'client.parse');
  });

  test('marks all read and reports how many changed', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data(3);
      }),
    );

    final result = await repository.markAllRead(fence: _fence);

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/v1/me/notifications/read-all');
    expect(result.fold<int?>((_) => null, (v) => v), 3);
  });

  test('a read-all response that is not a count is a parse failure', () async {
    final repository = _repository(
      _Auth(),
      MockClient((_) async => _data({'count': 3})),
    );

    final failure = _failure(await repository.markAllRead(fence: _fence));

    expect(failure?.code, 'client.parse');
  });

  test('writes are classified like reads', () async {
    final repository = _repository(
      _Auth(),
      MockClient((_) async => http.Response('', 500)),
    );

    final readFailure = _failure(
      await repository.markRead('notification-1', fence: _fence),
    );
    final readAllFailure = _failure(
      await repository.markAllRead(fence: _fence),
    );

    expect(readFailure?.code, 'server.error');
    expect(readAllFailure?.code, 'server.error');
  });
}
