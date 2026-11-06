import 'package:belog/core/error/failures.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/message_fakes.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

MessageThreadLoaded _loaded(MessageThreadCubit cubit) =>
    cubit.state as MessageThreadLoaded;

typedef _Harness = ({MessageThreadCubit cubit, MessageTestIdentity identity});

void main() {
  late FakeMessageRepository repository;
  late FakeParticipantNames names;

  setUp(() {
    repository = FakeMessageRepository()
      ..conversationResult = testConversation(unreadCount: 2)
      ..messagesResult = [
        testMessage(id: 'message-1', body: '第一条'),
        testMessage(id: 'message-2', body: '第二条', senderId: 'user-a'),
      ];
    names = FakeParticipantNames();
  });

  Future<_Harness> pumpThread({
    bool signedIn = true,
    String conversationId = 'conversation-1',
  }) async {
    final identity = MessageTestIdentity();
    if (!signedIn) {
      identity
        ..userId = null
        ..token = null;
    }
    addTearDown(identity.close);
    final cubit = MessageThreadCubit(
      conversationId: conversationId,
      repository: repository,
      identity: identity,
      names: names,
    );
    addTearDown(cubit.close);
    await cubit.load();
    return (cubit: cubit, identity: identity);
  }

  test('loads the header and the newest page, oldest first', () async {
    final harness = await pumpThread();

    final state = _loaded(harness.cubit);
    expect(state.viewerId, 'user-a');
    expect(state.messages.map((m) => m.id), ['message-1', 'message-2']);
    expect(state.conversation.unreadCount, 2);
    expect(state.participants['user-b']?.displayName, '读者乙');
    expect(repository.calls.first, 'conversation:conversation-1');
    expect(repository.calls.last, 'messages:conversation-1');
    expect(repository.beforeCursors.single, isNull);
  });

  test('nobody signed in means sign-in, not a missing conversation', () async {
    final harness = await pumpThread(signedIn: false);

    expect(harness.cubit.state, isA<MessageThreadSignedOut>());
    expect(repository.calls, isEmpty);
  });

  test(
    'a conversation this account cannot read is missing, not failed',
    () async {
      repository.conversationResult = null;
      final harness = await pumpThread();

      expect(harness.cubit.state, isA<MessageThreadMissing>());
      // A retry cannot help, so the screen offers none.
      expect(repository.calls, ['conversation:conversation-1']);
    },
  );

  test('a forbidden message list is missing too', () async {
    repository.messagesFailure = const Failure(
      '你没有权限查看这个会话',
      kind: FailureKind.permission,
      code: 'messages.forbidden',
    );
    final harness = await pumpThread();

    expect(harness.cubit.state, isA<MessageThreadMissing>());
  });

  test('a broken read is a retryable failure', () async {
    repository.messagesFailure = testOffline;
    final harness = await pumpThread();

    expect(harness.cubit.state, isA<MessageThreadFailure>());
    expect(
      (harness.cubit.state as MessageThreadFailure).failure.code,
      'network.unavailable',
    );
  });

  test('a full page means older messages exist', () async {
    repository.messagesResult = [
      for (var i = 0; i < MessageThreadCubit.pageLimit; i++)
        testMessage(id: 'message-$i'),
    ];
    final harness = await pumpThread();

    final state = _loaded(harness.cubit);
    expect(state.hasMore, isTrue);
    expect(state.olderCursor, 'message-0');
  });

  test('a short page means there is nothing older', () async {
    final harness = await pumpThread();

    expect(_loaded(harness.cubit).hasMore, isFalse);
  });

  test('loading older prepends the page before the cursor', () async {
    repository.messagesResult = [
      for (var i = 0; i < MessageThreadCubit.pageLimit; i++)
        testMessage(id: 'message-$i'),
    ];
    final harness = await pumpThread();
    expect(repository.beforeCursors, [null]);

    repository.messagesResult = [
      testMessage(id: 'older-1'),
      testMessage(id: 'older-2'),
    ];
    await harness.cubit.loadOlder();

    final state = _loaded(harness.cubit);
    expect(repository.beforeCursors.last, 'message-0');
    expect(state.messages.first.id, 'older-1');
    expect(state.messages[1].id, 'older-2');
    expect(state.messages[2].id, 'message-0');
    expect(state.hasMore, isFalse);
    expect(state.loadingOlder, isFalse);
  });

  test('a failed older page keeps what is already on screen', () async {
    repository.messagesResult = [
      for (var i = 0; i < MessageThreadCubit.pageLimit; i++)
        testMessage(id: 'message-$i'),
    ];
    final harness = await pumpThread();
    final count = _loaded(harness.cubit).messages.length;

    repository.messagesFailure = testOffline;
    await harness.cubit.loadOlder();

    final state = _loaded(harness.cubit);
    expect(state.messages, hasLength(count));
    expect(state.olderFailure?.code, 'network.unavailable');
    expect(state.loadingOlder, isFalse);
  });

  test('marking read clears the count once the server agrees', () async {
    final harness = await pumpThread();

    final failure = await harness.cubit.markRead();

    expect(failure, isNull);
    final state = _loaded(harness.cubit);
    expect(state.markedRead, isTrue);
    expect(state.conversation.unreadCount, 0);
    expect(repository.calls.last, 'markRead:conversation-1');
  });

  test('a read the server did not confirm leaves the count alone', () async {
    repository.markReadResult = false;
    final harness = await pumpThread();

    final failure = await harness.cubit.markRead();

    expect(failure, isNull);
    final state = _loaded(harness.cubit);
    expect(state.markedRead, isFalse);
    expect(state.conversation.unreadCount, 2);
  });

  test('a failed mark read reports the failure and keeps the count', () async {
    repository.markReadFailure = testOffline;
    final harness = await pumpThread();

    final failure = await harness.cubit.markRead();

    expect(failure?.code, 'network.unavailable');
    expect(_loaded(harness.cubit).conversation.unreadCount, 2);
    expect(_loaded(harness.cubit).markingRead, isFalse);
  });

  test('marking read is a no-op when nothing is unread', () async {
    repository.conversationResult = testConversation(unreadCount: 0);
    final harness = await pumpThread();

    await harness.cubit.markRead();

    expect(
      repository.calls.where((call) => call.startsWith('markRead')),
      isEmpty,
    );
  });

  test('sending appends the stored message', () async {
    final harness = await pumpThread();

    final failure = await harness.cubit.send(
      body: '新消息',
      idempotencyKey: 'key-1',
    );

    expect(failure, isNull);
    final state = _loaded(harness.cubit);
    expect(state.messages.last.body, '新消息');
    expect(state.messages.last.senderId, 'user-a');
    expect(repository.sendRequests.single.key, 'key-1');
    expect(state.sending, isFalse);
  });

  test('a replayed send does not list the message twice', () async {
    final harness = await pumpThread();
    repository.sendResult = testMessage(
      id: 'message-2',
      body: '第二条',
      senderId: 'user-a',
      duplicate: true,
    );

    await harness.cubit.send(body: '第二条', idempotencyKey: 'key-1');

    final state = _loaded(harness.cubit);
    expect(state.messages.where((m) => m.id == 'message-2'), hasLength(1));
  });

  test('a failed send keeps the thread and reports why', () async {
    final harness = await pumpThread();
    repository.sendFailure = testOffline;

    final failure = await harness.cubit.send(
      body: '新消息',
      idempotencyKey: 'key-1',
    );

    expect(failure?.code, 'network.unavailable');
    final state = _loaded(harness.cubit);
    expect(state.messages, hasLength(2));
    expect(state.sendFailure?.code, 'network.unavailable');
    expect(state.sending, isFalse);
  });

  test('a retry of the same text keeps its key', () async {
    final harness = await pumpThread();
    repository.sendFailure = testOffline;

    await harness.cubit.send(body: '新消息', idempotencyKey: 'key-1');
    await harness.cubit.send(body: '新消息', idempotencyKey: 'key-1');

    // The cubit never mints keys: the editor owns the intent, and a retry that
    // kept the text must keep the key too.
    expect(repository.sendRequests.map((request) => request.key), [
      'key-1',
      'key-1',
    ]);
  });

  test(
    'refresh picks up a header that changed while the page was open',
    () async {
      final harness = await pumpThread();
      expect(_loaded(harness.cubit).conversation.unreadCount, 2);

      repository.conversationResult = testConversation(unreadCount: 5);
      await harness.cubit.refresh();

      expect(_loaded(harness.cubit).conversation.unreadCount, 5);
      // Refresh does not re-read the page: the messages on screen stay.
      expect(_loaded(harness.cubit).messages, hasLength(2));
    },
  );

  test('an empty conversation is a real state, not a failure', () async {
    repository.messagesResult = const <ConversationMessage>[];
    final harness = await pumpThread();

    final state = _loaded(harness.cubit);
    expect(state.isEmpty, isTrue);
    expect(state.messages, isEmpty);
    expect(state.olderCursor, isNull);
  });

  test(
    'losing the session mid-thread stops writes instead of guessing',
    () async {
      final harness = await pumpThread();
      harness.identity.replace(null);
      await _settle();

      final failure = await harness.cubit.send(
        body: '新消息',
        idempotencyKey: 'key-1',
      );

      expect(failure, isNull);
      expect(harness.cubit.state, isA<MessageThreadSignedOut>());
      expect(repository.sendRequests, isEmpty);
    },
  );
}
