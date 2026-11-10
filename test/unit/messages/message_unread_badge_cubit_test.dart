import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/features/messages/presentation/bloc/message_unread_badge_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import '../../support/message_fakes.dart';

/// The badge only needs the list endpoint; the inherited fake keeps the other
/// repository methods out of these tests.
class _Repository extends FakeMessageRepository {
  final List<int> limits = [];
  final Map<String, List<Conversation>> conversationsByUser = {};
  String? gateUser;
  final Completer<void> gate = Completer<void>();

  @override
  Future<Either<Failure, List<Conversation>>> conversations({
    required NowaveSessionFence fence,
    int limit = 50,
  }) async {
    calls.add('conversations');
    fences.add(fence);
    limits.add(limit);
    if (fence.userId == gateUser) await gate.future;
    final failure = conversationsFailure;
    if (failure != null) return left(failure);
    return right(conversationsByUser[fence.userId] ?? conversationsResult);
  }
}

/// Lets the cubit's constructor-triggered read settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'sums unread messages and requests the same 50-row window as inbox',
    () async {
      final repository = _Repository()
        ..conversationsResult = [
          testConversation(unreadCount: 2),
          testConversation(id: 'conversation-2', unreadCount: 4),
          testConversation(id: 'conversation-3', unreadCount: 0),
        ];
      final identity = MessageTestIdentity();
      addTearDown(identity.close);
      final cubit = MessageUnreadBadgeCubit(
        repository: repository,
        identity: identity,
      );
      addTearDown(cubit.close);
      await _settle();

      expect(cubit.state, 6);
      expect(repository.calls, ['conversations']);
      expect(repository.limits, [MessageInboxCubit.pageLimit]);
      expect(repository.fences.single.userId, 'user-a');
      expect(repository.fences.single.generation, 1);
    },
  );

  test('caps an overlong response to 50 conversations', () async {
    final repository = _Repository()
      ..conversationsResult = [
        for (var index = 0; index < MessageInboxCubit.pageLimit + 1; index++)
          testConversation(id: 'conversation-$index', unreadCount: 1),
      ];
    final identity = MessageTestIdentity();
    addTearDown(identity.close);
    final cubit = MessageUnreadBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();

    expect(cubit.state, MessageInboxCubit.pageLimit);
  });

  test('nobody signed in means no badge and no request', () async {
    final repository = _Repository();
    final identity = MessageTestIdentity()
      ..userId = null
      ..token = null;
    addTearDown(identity.close);
    final cubit = MessageUnreadBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();

    expect(cubit.state, 0);
    expect(repository.calls, isEmpty);
  });

  test('a failed refresh keeps its last real count', () async {
    final repository = _Repository()
      ..conversationsResult = [testConversation(unreadCount: 7)];
    final identity = MessageTestIdentity();
    addTearDown(identity.close);
    final cubit = MessageUnreadBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();
    expect(cubit.state, 7);

    repository.conversationsFailure = testOffline;
    await cubit.refresh();

    expect(cubit.state, 7);
    expect(repository.calls, ['conversations', 'conversations']);
  });

  test('a cold read that fails shows no badge', () async {
    final repository = _Repository()..conversationsFailure = testOffline;
    final identity = MessageTestIdentity();
    addTearDown(identity.close);
    final cubit = MessageUnreadBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();

    expect(cubit.state, 0);
    expect(repository.calls, ['conversations']);
  });

  test(
    'a successful refresh updates the sum, including down to zero',
    () async {
      final repository = _Repository()
        ..conversationsResult = [testConversation(unreadCount: 3)];
      final identity = MessageTestIdentity();
      addTearDown(identity.close);
      final cubit = MessageUnreadBadgeCubit(
        repository: repository,
        identity: identity,
      );
      addTearDown(cubit.close);
      await _settle();
      expect(cubit.state, 3);

      repository.conversationsResult = [
        testConversation(unreadCount: 0),
        testConversation(id: 'conversation-2', unreadCount: 0),
      ];
      await cubit.refresh();

      expect(cubit.state, 0);
      expect(repository.calls, ['conversations', 'conversations']);
    },
  );

  test(
    'switching accounts clears the old count before reading the new one',
    () async {
      final repository = _Repository()
        ..conversationsByUser['user-a'] = [testConversation(unreadCount: 5)]
        ..conversationsByUser['user-b'] = [
          testConversation(
            id: 'conversation-b',
            participants: const ['user-b', 'user-c'],
            unreadCount: 1,
          ),
        ];
      final identity = MessageTestIdentity();
      addTearDown(identity.close);
      final cubit = MessageUnreadBadgeCubit(
        repository: repository,
        identity: identity,
      );
      addTearDown(cubit.close);
      await _settle();
      expect(cubit.state, 5);

      final emissions = <int>[];
      final subscription = cubit.stream.listen(emissions.add);
      addTearDown(subscription.cancel);
      identity.replace('user-b');
      await _settle();

      expect(emissions, [0, 1]);
      expect(cubit.state, 1);
      expect(repository.fences.map((fence) => fence.userId), [
        'user-a',
        'user-b',
      ]);
    },
  );

  test(
    'a late response from the previous account cannot replace the badge',
    () async {
      final repository = _Repository()
        ..gateUser = 'user-a'
        ..conversationsByUser['user-a'] = [testConversation(unreadCount: 9)]
        ..conversationsByUser['user-b'] = [
          testConversation(
            id: 'conversation-b',
            participants: const ['user-b', 'user-c'],
            unreadCount: 2,
          ),
        ];
      final identity = MessageTestIdentity();
      addTearDown(identity.close);
      final cubit = MessageUnreadBadgeCubit(
        repository: repository,
        identity: identity,
      );
      addTearDown(cubit.close);
      await _settle();

      identity.replace('user-b');
      await _settle();
      expect(cubit.state, 2);

      repository.gate.complete();
      await _settle();

      expect(cubit.state, 2);
      expect(repository.fences.map((fence) => fence.userId), [
        'user-a',
        'user-b',
      ]);
    },
  );

  test('signing out clears the badge', () async {
    final repository = _Repository()
      ..conversationsResult = [testConversation(unreadCount: 4)];
    final identity = MessageTestIdentity();
    addTearDown(identity.close);
    final cubit = MessageUnreadBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();
    expect(cubit.state, 4);

    identity.replace(null);
    await _settle();

    expect(cubit.state, 0);
    expect(repository.calls, ['conversations']);
  });
}
