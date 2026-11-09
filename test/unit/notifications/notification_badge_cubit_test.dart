import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/entities/notification_page.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_badge_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class _Identity implements NowaveSessionIdentity {
  String? userId = 'user-a';
  String? token = 'fake-token-a';
  int generation = 1;
  final controller = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;

  @override
  String? get accessToken => token;

  @override
  int get sessionGeneration => generation;

  @override
  Stream<void> get identityChanges => controller.stream;

  void replace(String? user) {
    generation++;
    userId = user;
    token = user == null ? null : 'fake-replacement-token';
    controller.add(null);
  }
}

class _Repository implements NotificationRepository {
  final fences = <NowaveSessionFence>[];
  int calls = 0;

  /// What each account's count is; a missing entry means zero.
  Map<String, int> counts = {'user-a': 3, 'user-b': 1};

  Failure? failure;

  /// When set, the response for this account waits until [gate] completes.
  String? gateUser;
  final gate = Completer<void>();

  @override
  Future<Either<Failure, int>> unreadCount({
    required NowaveSessionFence fence,
  }) async {
    calls++;
    fences.add(fence);
    if (gateUser == fence.userId) await gate.future;
    final failed = failure;
    if (failed != null) return left(failed);
    return right(counts[fence.userId] ?? 0);
  }

  @override
  Future<Either<Failure, NotificationPage>> list({
    required NowaveSessionFence fence,
    int limit = 50,
    String? cursor,
  }) async => right(const NotificationPage(items: [], nextCursor: null));

  @override
  Future<Either<Failure, AppNotification>> markRead(
    String id, {
    required NowaveSessionFence fence,
  }) async => throw UnimplementedError('the badge never marks a row read');

  @override
  Future<Either<Failure, int>> markAllRead({
    required NowaveSessionFence fence,
  }) async => throw UnimplementedError('the badge never marks rows read');
}

const _offline = Failure(
  '无法连接到网络，请检查网络设置',
  kind: FailureKind.network,
  code: 'network.unavailable',
);

/// Lets the cubit's fire-and-forget constructor load settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('shows the count the server reports', () async {
    final repository = _Repository();
    final identity = _Identity();
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();

    expect(cubit.state, 3);
    expect(repository.fences.single.userId, 'user-a');
    expect(repository.fences.single.generation, 1);
  });

  test('nobody signed in means no badge and no request', () async {
    final repository = _Repository();
    final identity = _Identity()
      ..userId = null
      ..token = null;
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();

    expect(cubit.state, 0);
    expect(repository.calls, 0);
  });

  test('a failed check keeps what it already knew', () async {
    final repository = _Repository();
    final identity = _Identity();
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();
    expect(cubit.state, 3);

    repository.failure = _offline;
    await cubit.refresh();

    // Offline is not "nothing unread": the badge keeps the last real number
    // instead of claiming zero.
    expect(cubit.state, 3);
  });

  test('a cold start that fails shows nothing', () async {
    final repository = _Repository()..failure = _offline;
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: _Identity(),
    );
    addTearDown(cubit.close);
    await _settle();

    expect(cubit.state, 0);
  });

  test('signing in as someone else never inherits the old count', () async {
    final repository = _Repository();
    final identity = _Identity();
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();
    expect(cubit.state, 3);

    final seen = <int>[];
    final subscription = cubit.stream.listen(seen.add);
    addTearDown(subscription.cancel);
    identity.replace('user-b');
    await _settle();

    // Zero first, then the new account's number: never 3 for user-b.
    expect(seen.toSet(), {0, 1});
    expect(seen.first, 0);
    expect(cubit.state, 1);
  });

  test('signing out clears the badge', () async {
    final repository = _Repository();
    final identity = _Identity();
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();
    expect(cubit.state, 3);

    identity.replace(null);
    await _settle();

    expect(cubit.state, 0);
  });

  test('a slow response for the previous account is dropped', () async {
    final repository = _Repository()..gateUser = 'user-a';
    final identity = _Identity();
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: identity,
    );
    addTearDown(cubit.close);
    await _settle();

    // The switch happens while user-a's request is still in flight.
    identity.replace('user-b');
    await _settle();
    expect(cubit.state, 1);

    repository.gate.complete();
    await _settle();

    // user-a's late "3" must not be shown to user-b.
    expect(cubit.state, 1);
  });

  test('refresh asks again and follows the server down to zero', () async {
    final repository = _Repository();
    final cubit = NotificationBadgeCubit(
      repository: repository,
      identity: _Identity(),
    );
    addTearDown(cubit.close);
    await _settle();
    expect(cubit.state, 3);

    repository.counts = {'user-a': 0};
    await cubit.refresh();

    expect(cubit.state, 0);
    expect(repository.calls, 2);
  });
}
