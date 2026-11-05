import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
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
  final calls = <String>[];

  /// Rows returned per account.
  Map<String, List<AppNotification>> rowsByUser = {};

  Failure? listFailure;
  Failure? markFailure;
  Failure? markAllFailure;

  /// When set, a list call for this account waits until [gate] completes.
  String? gateUser;
  final gate = Completer<void>();

  @override
  Future<Either<Failure, List<AppNotification>>> list({
    required NowaveSessionFence fence,
    int limit = 50,
  }) async {
    fences.add(fence);
    calls.add('list');
    if (gateUser == fence.userId) await gate.future;
    final failure = listFailure;
    if (failure != null) return left(failure);
    return right(rowsByUser[fence.userId] ?? const []);
  }

  @override
  Future<Either<Failure, AppNotification>> markRead(
    String id, {
    required NowaveSessionFence fence,
  }) async {
    fences.add(fence);
    calls.add('markRead:$id');
    final failure = markFailure;
    if (failure != null) return left(failure);
    final rows = rowsByUser[fence.userId] ?? const <AppNotification>[];
    final updated = rows
        .firstWhere((row) => row.id == id)
        .markedRead(DateTime.utc(2026, 11, 5, 7));
    rowsByUser[fence.userId] = [
      for (final row in rows)
        if (row.id == id) updated else row,
    ];
    return right(updated);
  }

  @override
  Future<Either<Failure, int>> markAllRead({
    required NowaveSessionFence fence,
  }) async {
    fences.add(fence);
    calls.add('markAllRead');
    final failure = markAllFailure;
    if (failure != null) return left(failure);
    return right(1);
  }
}

AppNotification _notification({
  String id = 'notification-1',
  AppNotificationKind kind = AppNotificationKind.articleDeleted,
  DateTime? readAt,
}) => AppNotification(
  id: id,
  eventKey: 'event:$id',
  kind: kind,
  createdAt: DateTime.utc(2026, 11, 5, 4, 30),
  readAt: readAt,
  articleId: kind == AppNotificationKind.articleDeleted ? 'article-9' : null,
  conversationId: kind == AppNotificationKind.messageReceived
      ? 'conversation-1'
      : null,
);

const _offline = Failure(
  '无法连接到网络，请检查网络设置',
  kind: FailureKind.network,
  code: 'network.unavailable',
);

NotificationInboxLoaded _loaded(NotificationInboxCubit cubit) =>
    cubit.state as NotificationInboxLoaded;

void main() {
  late _Identity identity;
  late _Repository repository;
  late NotificationInboxCubit cubit;

  Future<void> pumpCubit({
    Map<String, List<AppNotification>> rows = const {},
    void Function(_Repository repository)? configure,
  }) async {
    identity = _Identity();
    repository = _Repository()..rowsByUser = {...rows};
    configure?.call(repository);
    cubit = NotificationInboxCubit(repository: repository, identity: identity);
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() async {
    await cubit.close();
    await identity.controller.close();
  });

  test('reads the inbox for the signed-in account and generation', () async {
    await pumpCubit(
      rows: {
        'user-a': [
          _notification(),
          _notification(
            id: 'notification-2',
            kind: AppNotificationKind.messageReceived,
          ),
        ],
      },
    );

    final state = _loaded(cubit);
    expect(state.items, hasLength(2));
    expect(state.unreadCount, 2);
    expect(repository.calls, ['list']);
    expect(repository.fences.single.userId, 'user-a');
    expect(repository.fences.single.generation, 1);
  });

  test('nobody signed in means a sign-in state and no request', () async {
    await pumpCubit();
    repository.calls.clear();

    identity.replace(null);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<NotificationInboxSignedOut>());
    expect(repository.calls, isEmpty);
  });

  test('a failed read is shown, and retrying can succeed', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification()],
      },
      configure: (repository) => repository.listFailure = _offline,
    );
    expect(
      (cubit.state as NotificationInboxFailure).failure.code,
      'network.unavailable',
    );

    repository.listFailure = null;
    await cubit.load();

    expect(_loaded(cubit).items, hasLength(1));
  });

  test('marking one read replaces that row only', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification(), _notification(id: 'notification-2')],
      },
    );

    final failure = await cubit.markRead('notification-1');

    final state = _loaded(cubit);
    expect(failure, isNull);
    expect(state.markingId, isNull);
    expect(state.items.first.isRead, isTrue);
    expect(state.items.last.isRead, isFalse);
    expect(state.unreadCount, 1);
    expect(repository.calls.last, 'markRead:notification-1');
  });

  test('a failed mark read leaves the row unread and says why', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification()],
      },
    );
    repository.markFailure = _offline;

    final failure = await cubit.markRead('notification-1');

    final state = _loaded(cubit);
    expect(failure?.code, 'network.unavailable');
    expect(state.markingId, isNull);
    expect(state.items.single.isRead, isFalse);
  });

  test('marking all read clears every unread row', () async {
    await pumpCubit(
      rows: {
        'user-a': [
          _notification(),
          _notification(
            id: 'notification-2',
            kind: AppNotificationKind.messageReceived,
          ),
          _notification(
            id: 'notification-3',
            readAt: DateTime.utc(2026, 11, 5),
          ),
        ],
      },
    );

    final failure = await cubit.markAllRead();

    final state = _loaded(cubit);
    expect(failure, isNull);
    expect(state.markingAll, isFalse);
    expect(state.unreadCount, 0);
    // The server's first read time is never rewritten locally.
    expect(state.items.last.readAt, DateTime.utc(2026, 11, 5));
    expect(repository.calls.last, 'markAllRead');
  });

  test('marking all read with nothing unread sends nothing', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification(readAt: DateTime.utc(2026, 11, 5))],
      },
    );

    expect(await cubit.markAllRead(), isNull);
    expect(repository.calls, isNot(contains('markAllRead')));
  });

  test('a failed mark all read keeps the rows unread', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification(), _notification(id: 'notification-2')],
      },
    );
    repository.markAllFailure = _offline;

    final failure = await cubit.markAllRead();

    final state = _loaded(cubit);
    expect(failure?.code, 'network.unavailable');
    expect(state.markingAll, isFalse);
    expect(state.unreadCount, 2);
  });

  test('a read that lands after an account switch is dropped', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification(id: 'row-a')],
        'user-b': [_notification(id: 'row-b')],
      },
    );
    repository.gateUser = 'user-a';

    final staleLoad = cubit.load();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, isA<NotificationInboxLoading>());

    identity.replace('user-b');
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(cubit).items.single.id, 'row-b');

    repository.gate.complete();
    await staleLoad;
    await Future<void>.delayed(Duration.zero);

    expect(_loaded(cubit).items.single.id, 'row-b');
    expect(repository.fences.last.userId, 'user-b');
  });

  test(
    'a mark read by the previous account cannot touch the new inbox',
    () async {
      await pumpCubit(
        rows: {
          'user-a': [_notification(id: 'row-a')],
        },
      );

      final staleMark = cubit.markRead('row-a');
      repository.rowsByUser['user-b'] = [_notification(id: 'row-b')];
      identity.replace('user-b');
      await Future<void>.delayed(Duration.zero);
      await staleMark;

      final state = _loaded(cubit);
      expect(state.items.single.id, 'row-b');
      expect(state.items.single.isRead, isFalse);
    },
  );
}
