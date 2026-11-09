import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/message_fakes.dart';

/// Lets a cubit's fire-and-forget work settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

MessageInboxLoaded _loaded(MessageInboxCubit cubit) =>
    cubit.state as MessageInboxLoaded;

typedef _Harness = ({MessageInboxCubit cubit, MessageTestIdentity identity});

void main() {
  late FakeMessageRepository repository;
  late FakeParticipantNames names;

  setUp(() {
    repository = FakeMessageRepository();
    names = FakeParticipantNames();
  });

  /// Builds the cubit and waits for its first read.
  Future<_Harness> pumpInbox({bool signedIn = true}) async {
    final identity = MessageTestIdentity();
    if (!signedIn) {
      identity
        ..userId = null
        ..token = null;
    }
    addTearDown(identity.close);
    final cubit = MessageInboxCubit(
      repository: repository,
      identity: identity,
      names: names,
    );
    addTearDown(cubit.close);
    await _settle();
    return (cubit: cubit, identity: identity);
  }

  test('nobody signed in means an empty inbox and no request', () async {
    final harness = await pumpInbox(signedIn: false);

    expect(harness.cubit.state, isA<MessageInboxSignedOut>());
    expect(repository.calls, isEmpty);
  });

  test('loads the list and then resolves the other participants', () async {
    repository.conversationsResult = [
      testConversation(unreadCount: 2),
      testConversation(
        id: 'conversation-2',
        participants: ['user-a', 'user-c'],
      ),
    ];
    final harness = await pumpInbox();

    final state = _loaded(harness.cubit);
    expect(state.viewerId, 'user-a');
    expect(state.conversations, hasLength(2));
    expect(state.participants['user-b']?.displayName, '读者乙');
    expect(state.participants['user-c']?.displayName, '读者丙');
    // The viewer's own id is never resolved into a name.
    expect(names.lookups, ['user-b', 'user-c']);
    expect(repository.fences.single.userId, 'user-a');
    expect(repository.calls, ['conversations']);
  });

  test('the list is usable while names are still missing', () async {
    repository.conversationsResult = [testConversation()];
    names.failAll = true;
    final harness = await pumpInbox();

    final state = _loaded(harness.cubit);
    expect(state.conversations, hasLength(1));
    expect(state.participants, isEmpty);
  });

  test('a failed load is a failure state, not an empty inbox', () async {
    repository.conversationsFailure = testOffline;
    final harness = await pumpInbox();

    expect(harness.cubit.state, isA<MessageInboxFailure>());
    expect(
      (harness.cubit.state as MessageInboxFailure).failure.code,
      'network.unavailable',
    );
  });

  test('a silent refresh keeps the rows on screen', () async {
    repository.conversationsResult = [testConversation()];
    final harness = await pumpInbox();
    expect(_loaded(harness.cubit).conversations, hasLength(1));

    final states = <MessageInboxState>[];
    final subscription = harness.cubit.stream.listen(states.add);
    addTearDown(subscription.cancel);
    repository.conversationsResult = [
      testConversation(),
      testConversation(id: 'conversation-2'),
    ];
    await harness.cubit.load(showLoading: false);
    await _settle();

    // No loading state in between: the old rows never disappear.
    expect(states.whereType<MessageInboxLoading>(), isEmpty);
    expect(_loaded(harness.cubit).conversations, hasLength(2));
  });

  test('switching accounts reads the list for the new account', () async {
    repository.conversationsResult = [testConversation(unreadCount: 3)];
    final harness = await pumpInbox();
    expect(_loaded(harness.cubit).viewerId, 'user-a');

    repository.conversationsResult = [
      testConversation(participants: ['user-b', 'user-c']),
    ];
    harness.identity.replace('user-b');
    await _settle();
    await _settle();

    final state = _loaded(harness.cubit);
    expect(state.viewerId, 'user-b');
    expect(state.conversations.single.participantIds, ['user-b', 'user-c']);
    expect(repository.fences.last.userId, 'user-b');
  });

  test('a response that belongs to the previous account is dropped', () async {
    final gate = Completer<void>();
    repository.conversationsGate = gate;
    repository.conversationsResult = [testConversation(unreadCount: 9)];
    final harness = await pumpInbox();
    // The first read is now waiting behind the gate, fenced to user-a.

    harness.identity.replace('user-b');
    await _settle();
    repository.conversationsResult = [
      testConversation(
        id: 'new-conversation',
        participants: ['user-b', 'user-c'],
      ),
    ];
    repository.conversationsGate = null;
    gate.complete();
    await _settle();
    await _settle();

    // user-a's late nine-unread row never becomes user-b's list.
    final state = _loaded(harness.cubit);
    expect(state.viewerId, 'user-b');
    expect(state.conversations.single.id, 'new-conversation');
  });

  test(
    'only the creator can delete, and a refusal makes no request',
    () async {
      repository.conversationsResult = [
        testConversation(participants: ['user-b', 'user-a']),
      ];
      final harness = await pumpInbox();

      final result = await harness.cubit.deleteConversation('conversation-1');

      expect(
        result.fold((failure) => failure.code, (_) => null),
        'messages.deleteForbidden',
      );
      expect(repository.deletedConversationIds, isEmpty);
      expect(_loaded(harness.cubit).conversations, hasLength(1));
    },
  );

  test(
    'a confirmed delete removes the row and filters stale list reads',
    () async {
      repository.conversationsResult = [
        testConversation(),
        testConversation(
          id: 'conversation-2',
          participants: ['user-a', 'user-c'],
        ),
      ];
      final harness = await pumpInbox();

      final result = await harness.cubit.deleteConversation('conversation-1');

      expect(result.fold((_) => null, (deleted) => deleted), isTrue);
      expect(repository.deletedConversationIds, ['conversation-1']);
      expect(repository.fences.last.userId, 'user-a');
      expect(
        _loaded(harness.cubit).conversations.map((row) => row.id),
        ['conversation-2'],
      );
      expect(_loaded(harness.cubit).deletingConversationId, isNull);

      // The next inbox refresh cannot restore the deleted row.
      await harness.cubit.load(showLoading: false);
      expect(
        _loaded(harness.cubit).conversations.map((row) => row.id),
        ['conversation-2'],
      );
    },
  );

  test('a false delete response leaves reconciliation to the inbox', () async {
    repository.conversationsResult = [testConversation()];
    repository.deleteConversationResult = false;
    final harness = await pumpInbox();

    final result = await harness.cubit.deleteConversation('conversation-1');

    expect(result.fold((_) => null, (deleted) => deleted), isFalse);
    expect(_loaded(harness.cubit).conversations, hasLength(1));
    expect(_loaded(harness.cubit).deletingConversationId, isNull);
  });

  test(
    'a failed delete retains the row and clears its in-flight marker',
    () async {
      repository.conversationsResult = [testConversation()];
      repository.deleteConversationFailure = testOffline;
      final harness = await pumpInbox();

      final result = await harness.cubit.deleteConversation('conversation-1');

      expect(
        result.fold((failure) => failure.code, (_) => null),
        'network.unavailable',
      );
      expect(_loaded(harness.cubit).conversations, hasLength(1));
      expect(_loaded(harness.cubit).deletingConversationId, isNull);
    },
  );

  test(
    'refresh cannot start a second delete while the first is in flight',
    () async {
      repository.conversationsResult = [testConversation()];
      final gate = Completer<void>();
      repository.deleteConversationGate = gate;
      final harness = await pumpInbox();

      final pending = harness.cubit.deleteConversation('conversation-1');
      await _settle();
      await harness.cubit.load(showLoading: false);
      expect(_loaded(harness.cubit).deletingConversationId, 'conversation-1');

      final second = await harness.cubit.deleteConversation('conversation-1');
      expect(
        second.fold((failure) => failure.code, (_) => null),
        'messages.deleteInProgress',
      );
      expect(repository.deletedConversationIds, ['conversation-1']);

      gate.complete();
      await pending;
      expect(_loaded(harness.cubit).conversations, isEmpty);
    },
  );

  test(
    'a delete response from an old account does not update the new inbox',
    () async {
      repository.conversationsResult = [testConversation()];
      final gate = Completer<void>();
      repository.deleteConversationGate = gate;
      final harness = await pumpInbox();

      final pending = harness.cubit.deleteConversation('conversation-1');
      await _settle();
      expect(_loaded(harness.cubit).deletingConversationId, 'conversation-1');

      harness.identity.replace('user-b');
      await _settle();
      await _settle();
      gate.complete();
      final result = await pending;

      expect(
        result.fold((failure) => failure.code, (_) => null),
        'auth.sessionChanged',
      );
      expect(_loaded(harness.cubit).viewerId, 'user-b');
      expect(_loaded(harness.cubit).conversations, hasLength(1));
    },
  );

  test('a conversation that already exists with someone is reused', () async {
    repository.conversationsResult = [
      testConversation(id: 'existing'),
      testConversation(id: 'other', participants: ['user-a', 'user-c']),
    ];
    final harness = await pumpInbox();
    final before = repository.calls.length;

    final result = await harness.cubit.startConversation('user-b');

    expect(result.fold((_) => null, (id) => id), 'existing');
    // Reusing means not asking the server to open a second thread.
    expect(repository.calls.length, before);
  });

  test('the first start mints a key, and a retry reuses it', () async {
    repository.startFailure = testOffline;
    final harness = await pumpInbox();

    final first = await harness.cubit.startConversation('user-b');
    final second = await harness.cubit.startConversation('user-b');

    expect(first.isLeft(), isTrue);
    expect(second.isLeft(), isTrue);
    expect(repository.startRequests, hasLength(2));
    expect(repository.startRequests[0].key, isNotEmpty);
    // A lost response must not become a second conversation.
    expect(repository.startRequests[1].key, repository.startRequests[0].key);
  });

  test('a conflicting key is discarded so the retry mints a new one', () async {
    repository.startFailure = const Failure(
      '重复提交的内容不一致，请刷新后重试',
      kind: FailureKind.validation,
      code: 'server.IDEMPOTENCY_CONFLICT',
    );
    final harness = await pumpInbox();

    await harness.cubit.startConversation('user-b');
    await harness.cubit.startConversation('user-b');

    expect(
      repository.startRequests[1].key,
      isNot(repository.startRequests[0].key),
    );
  });

  test('a different recipient gets its own key', () async {
    repository.startFailure = testOffline;
    final harness = await pumpInbox();

    await harness.cubit.startConversation('user-b');
    await harness.cubit.startConversation('user-c');

    expect(
      repository.startRequests[1].key,
      isNot(repository.startRequests[0].key),
    );
  });

  test('a successful start returns the id and reloads the list', () async {
    repository.startResult = testConversation(id: 'created');
    final harness = await pumpInbox();
    final before = repository.calls
        .where((call) => call == 'conversations')
        .length;

    final result = await harness.cubit.startConversation('user-b');
    await _settle();

    expect(result.fold((_) => null, (id) => id), 'created');
    expect(
      repository.calls.where((call) => call == 'conversations').length,
      before + 1,
    );
    expect(_loaded(harness.cubit).startingRecipient, isNull);
  });

  test('messaging yourself is refused without a request', () async {
    final harness = await pumpInbox();
    final before = repository.calls.length;

    final result = await harness.cubit.startConversation('user-a');

    expect(result.isLeft(), isTrue);
    expect(repository.calls.length, before);
  });

  test('starting marks the recipient as in flight while it runs', () async {
    final harness = await pumpInbox();
    final states = <MessageInboxState>[];
    final subscription = harness.cubit.stream.listen(states.add);
    addTearDown(subscription.cancel);

    await harness.cubit.startConversation('user-b');
    await _settle();

    final starting = states
        .whereType<MessageInboxLoaded>()
        .map((state) => state.startingRecipient)
        .whereType<String>()
        .toList();
    expect(starting, ['user-b']);
  });

  test('a second start while one runs is refused', () async {
    repository.startFailure = testOffline;
    final harness = await pumpInbox();

    final pending = harness.cubit.startConversation('user-b');
    final second = await harness.cubit.startConversation('user-c');
    await pending;

    expect(second.isLeft(), isTrue);
    expect(repository.startRequests, hasLength(1));
  });

  test('existingWith only matches a one-to-one conversation', () async {
    repository.conversationsResult = [
      testConversation(
        id: 'group',
        participants: ['user-a', 'user-b', 'user-c'],
      ),
    ];
    final harness = await pumpInbox();

    expect(_loaded(harness.cubit).existingWith('user-b'), isNull);
  });
}
