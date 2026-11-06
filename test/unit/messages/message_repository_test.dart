import 'dart:convert';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/messages/data/repositories/message_repository_impl.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth implements NowaveViewerAuthenticator {
  String? user = 'user-a';
  String? token = 'fake-token-a';
  int generation = 1;

  @override
  String? get accessToken => token;

  @override
  String? get activeUserId => user;

  @override
  int get sessionGeneration => generation;

  @override
  Future<bool> refresh() async => false;

  void replace() {
    generation++;
    user = 'user-b';
    token = 'fake-token-b';
  }
}

const _fence = NowaveSessionFence(userId: 'user-a', generation: 1);

MessageRepositoryImpl _repository(_Auth auth, MockClient httpClient) =>
    MessageRepositoryImpl(
      NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        authenticator: auth,
        httpClient: httpClient,
      ),
    );

Map<String, dynamic> _messageRow({
  String id = 'message-1',
  String conversationId = 'conversation-1',
  String senderId = 'user-b',
  String body = '你好',
  String createdAt = '2026-11-05T04:30:00.000Z',
  Object? duplicate,
}) => {
  'id': id,
  'conversationId': conversationId,
  'senderId': senderId,
  'body': body,
  'createdAt': createdAt,
  if (duplicate != null) 'duplicate': duplicate,
};

Map<String, dynamic> _conversationRow({
  String id = 'conversation-1',
  List<String> participants = const ['user-a', 'user-b'],
  int unreadCount = 2,
  Map<String, dynamic>? lastMessage,
  bool withLastMessage = true,
}) => {
  'id': id,
  'createdBy': 'user-a',
  'participantIds': participants,
  'createdAt': '2026-11-05T04:00:00.000Z',
  'lastActivityAt': '2026-11-05T04:30:00.000Z',
  'unreadCount': unreadCount,
  'lastMessage': withLastMessage
      ? (lastMessage ?? _messageRow())
      : null,
};

http.Response _data(Object? value, {int status = 200}) =>
    http.Response(jsonEncode({'data': value}), status);

Failure? _failure(Either<Failure, Object?> result) =>
    result.fold((failure) => failure, (_) => null);

void main() {
  test('lists conversations with a bounded limit and no redirects', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data([_conversationRow()]);
      }),
    );

    final result = await repository.conversations(fence: _fence);
    final rows = result.fold<List<Conversation>?>((_) => null, (v) => v)!;

    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/v1/conversations');
    expect(seen.single.url.queryParameters['limit'], '50');
    expect(seen.single.followRedirects, isFalse);
    expect(seen.single.headers['authorization'], 'Bearer fake-token-a');
    expect(rows.single.id, 'conversation-1');
    expect(rows.single.participantIds, ['user-a', 'user-b']);
    expect(rows.single.unreadCount, 2);
    expect(rows.single.lastMessage?.body, '你好');
    expect(rows.single.lastMessage?.senderId, 'user-b');
    expect(() => rows.clear(), throwsUnsupportedError);
  });

  test('keeps a request inside the server maximum', () async {
    final limits = <String?>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        limits.add(request.url.queryParameters['limit']);
        return _data(const []);
      }),
    );

    await repository.conversations(fence: _fence, limit: 1000);
    await repository.conversations(fence: _fence, limit: 0);
    await repository.conversations(fence: _fence, limit: 100);

    expect(limits, ['100', '1', '100']);
  });

  test('reads one conversation header', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data(_conversationRow(unreadCount: 0));
      }),
    );

    final result = await repository.conversation(
      'conversation-1',
      fence: _fence,
    );

    expect(seen.single.url.path, '/api/v1/conversations/conversation-1');
    expect(result.fold((_) => null, (v) => v)?.unreadCount, 0);
  });

  test('reads the newest page, and the page before a cursor', () async {
    final urls = <Uri>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        urls.add(request.url);
        return _data([_messageRow()]);
      }),
    );

    await repository.messages('conversation-1', fence: _fence);
    await repository.messages(
      'conversation-1',
      fence: _fence,
      before: 'message-9',
    );

    expect(urls[0].path, '/api/v1/conversations/conversation-1/messages');
    expect(urls[0].queryParameters['limit'], '100');
    expect(urls[0].queryParameters.containsKey('before'), isFalse);
    expect(urls[1].queryParameters['before'], 'message-9');
  });

  test('an empty cursor is refused before it reaches the server', () async {
    var requests = 0;
    final repository = _repository(
      _Auth(),
      MockClient((_) async {
        requests++;
        return _data(const []);
      }),
    );

    final failure = _failure(
      await repository.messages('conversation-1', fence: _fence, before: ''),
    );

    // Forwarded, an empty cursor would read as a client bug on the server.
    expect(requests, 0);
    expect(failure?.code, 'client.parse');
  });

  test('marks a conversation read with an empty body', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data(true);
      }),
    );

    final result = await repository.markRead('conversation-1', fence: _fence);

    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '/api/v1/conversations/conversation-1/read');
    expect(seen.single.body, isEmpty);
    expect(result.fold((_) => null, (v) => v), isTrue);
  });

  test('a read the server did not confirm is not reported as read', () async {
    final repository = _repository(
      _Auth(),
      MockClient((_) async => _data(false)),
    );

    final result = await repository.markRead('conversation-1', fence: _fence);

    expect(result.fold((_) => null, (v) => v), isFalse);
  });

  test('starts a conversation with an idempotency key', () async {
    final seen = <http.Request>[];
    final repository = _repository(
      _Auth(),
      MockClient((request) async {
        seen.add(request);
        return _data(_conversationRow(unreadCount: 0), status: 201);
      }),
    );

    final result = await repository.startConversation(
      fence: _fence,
      recipientId: 'user-b',
      idempotencyKey: 'key-1',
    );

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/v1/conversations');
    expect(seen.single.headers['idempotency-key'], 'key-1');
    expect(jsonDecode(seen.single.body), {
      'participantIds': ['user-b'],
    });
    expect(result.fold((_) => null, (v) => v)?.id, 'conversation-1');
  });

  group('a start this build cannot honour is refused locally', () {
    final cases = <String, ({String recipient, String key})>{
      'yourself': (recipient: 'user-a', key: 'key-1'),
      'an untrimmed id': (recipient: ' user-b', key: 'key-1'),
      'an empty id': (recipient: '', key: 'key-1'),
      'a missing key': (recipient: 'user-b', key: ''),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        var requests = 0;
        final repository = _repository(
          _Auth(),
          MockClient((_) async {
            requests++;
            return _data(_conversationRow());
          }),
        );

        final failure = _failure(
          await repository.startConversation(
            fence: _fence,
            recipientId: entry.value.recipient,
            idempotencyKey: entry.value.key,
          ),
        );

        expect(requests, 0);
        expect(failure?.code, 'messages.invalid');
      });
    }
  });

  test(
    'sends a message with an idempotency key and reads the replay flag',
    () async {
      final seen = <http.Request>[];
      final repository = _repository(
        _Auth(),
        MockClient((request) async {
          seen.add(request);
          return _data(_messageRow(duplicate: true), status: 201);
        }),
      );

      final result = await repository.sendMessage(
        'conversation-1',
        fence: _fence,
        body: '你好',
        idempotencyKey: 'key-2',
      );
      final message = result.fold<ConversationMessage?>((_) => null, (v) => v)!;

      expect(seen.single.method, 'POST');
      expect(
        seen.single.url.path,
        '/api/v1/conversations/conversation-1/messages',
      );
      expect(seen.single.headers['idempotency-key'], 'key-2');
      expect(jsonDecode(seen.single.body), {'body': '你好'});
      expect(message.body, '你好');
      expect(message.duplicate, isTrue);
    },
  );

  group('a message the server would reject is refused locally', () {
    final cases = <String, ({String body, String key})>{
      'an empty body': (body: '', key: 'key-2'),
      'a body with edge whitespace': (body: ' 你好 ', key: 'key-2'),
      'a body over 20000 characters': (
        body: 'a' * 20001,
        key: 'key-2',
      ),
      'a missing key': (body: '你好', key: ''),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        var requests = 0;
        final repository = _repository(
          _Auth(),
          MockClient((_) async {
            requests++;
            return _data(_messageRow());
          }),
        );

        final failure = _failure(
          await repository.sendMessage(
            'conversation-1',
            fence: _fence,
            body: entry.value.body,
            idempotencyKey: entry.value.key,
          ),
        );

        expect(requests, 0);
        expect(failure?.code, 'messages.invalid');
      });
    }
  });

  test('a 20000-character body is allowed, one more is not', () async {
    final repository = _repository(
      _Auth(),
      MockClient((_) async => _data(_messageRow(), status: 201)),
    );

    final result = await repository.sendMessage(
      'conversation-1',
      fence: _fence,
      body: 'a' * 20000,
      idempotencyKey: 'key-3',
    );

    expect(result.isRight(), isTrue);
  });

  for (final entry in <int, String>{
    400: 'messages.invalid',
    401: 'server.UNAUTHENTICATED',
    403: 'messages.forbidden',
    404: 'messages.missing',
    405: 'messages.unavailable',
    429: 'server.RATE_LIMITED',
    500: 'server.error',
  }.entries) {
    test('HTTP ${entry.key} on a conversation is classified', () async {
      final repository = _repository(
        _Auth(),
        MockClient(
          (_) async => http.Response('private server message', entry.key),
        ),
      );

      final failure = _failure(
        await repository.messages('conversation-1', fence: _fence),
      );

      expect(failure?.code, entry.value);
      expect(failure?.message, isNot(contains('private server message')));
      expect(failure?.cause, isNull);
    });
  }

  test(
    'a 409 idempotency conflict is told apart from a state conflict',
    () async {
      final repository = _repository(
        _Auth(),
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'IDEMPOTENCY_CONFLICT',
                'message': 'The idempotency key was already used.',
              },
            }),
            409,
          ),
        ),
      );

      final failure = _failure(
        await repository.sendMessage(
          'conversation-1',
          fence: _fence,
          body: '你好',
          idempotencyKey: 'key-1',
        ),
      );

      // The reader's next move is "discard and retry", not "refresh".
      expect(failure?.code, 'server.IDEMPOTENCY_CONFLICT');
    },
  );

  test(
    '404 on the collection endpoints means the deployment lacks messages',
    () async {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => http.Response('missing', 404)),
      );

      final failure = _failure(await repository.conversations(fence: _fence));

      // A conversation list has no per-row identity to be missing: 404 here is
      // an older server, not a conversation that went away.
      expect(failure?.code, 'messages.unavailable');
    },
  );

  group('a success response this build cannot read is a parse failure', () {
    final cases =
        <
          String,
          (
            http.Response,
            Future<Either<Failure, Object?>> Function(MessageRepositoryImpl),
          )
        >{
          'a conversation list that is not a list': (
            _data({'rows': []}),
            (repository) => repository.conversations(fence: _fence),
          ),
          'a conversation row that is not an object': (
            _data(['conversation-1']),
            (repository) => repository.conversations(fence: _fence),
          ),
          'a conversation without participants': (
            _data([
              _conversationRow()..remove('participantIds'),
            ]),
            (repository) => repository.conversations(fence: _fence),
          ),
          'a conversation with a negative unread count': (
            _data([
              _conversationRow(unreadCount: -1),
            ]),
            (repository) => repository.conversations(fence: _fence),
          ),
          'a conversation with a naive timestamp': (
            _data([
              _conversationRow()..['lastActivityAt'] = '2026-11-05T04:30:00',
            ]),
            (repository) => repository.conversations(fence: _fence),
          ),
          'a message row without a body': (
            _data([
              _messageRow()..remove('body'),
            ]),
            (repository) =>
                repository.messages('conversation-1', fence: _fence),
          ),
          'a body that is not JSON': (
            http.Response('not json', 200),
            (repository) => repository.conversations(fence: _fence),
          ),
        };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final repository = _repository(
          _Auth(),
          MockClient((_) async => entry.value.$1),
        );

        final failure = _failure(await entry.value.$2(repository));

        expect(failure?.code, 'client.parse');
      });
    }

    // The strictness above must not reject a well-formed row.
    test('a valid list still reads', () async {
      final repository = _repository(
        _Auth(),
        MockClient((_) async => _data([_conversationRow()])),
      );

      expect(
        (await repository.conversations(fence: _fence)).isRight(),
        isTrue,
      );
    });
  });

  test('a replaced account cannot read the old conversations', () async {
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

    final failure = _failure(await repository.conversations(fence: _fence));

    expect(requests, 0);
    expect(failure?.code, 'auth.sessionChanged');
  });

  test('an invalid conversation id never reaches the server', () async {
    var requests = 0;
    final repository = _repository(
      _Auth(),
      MockClient((_) async {
        requests++;
        return _data(const []);
      }),
    );

    final failure = _failure(await repository.messages('', fence: _fence));

    expect(requests, 0);
    expect(failure?.code, 'client.parse');
  });
}
