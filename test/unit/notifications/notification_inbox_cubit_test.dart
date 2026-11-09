import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/entities/notification_page.dart';
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

  /// Rows returned per account when no cursor-specific fixture is configured.
  Map<String, List<AppNotification>> rowsByUser = {};
  final cursors = <String?>[];

  /// Exact pages keyed by account and the cursor used to request them.
  Map<String, Map<String?, NotificationPage>> pagesByCursor = {};

  Failure? listFailure;
  Failure? markFailure;
  Failure? markAllFailure;

  /// When set, a list call for this account waits until [gate] completes.
  String? gateUser;
  final gate = Completer<void>();

  @override
  Future<Either<Failure, NotificationPage>> list({
    required NowaveSessionFence fence,
    int limit = 50,
    String? cursor,
  }) async {
    fences.add(fence);
    calls.add('list');
    cursors.add(cursor);
    if (gateUser == fence.userId) await gate.future;
    final failure = listFailure;
    if (failure != null) return left(failure);
    final configuredPages = pagesByCursor[fence.userId];
    if (configuredPages != null) {
      return right(
        configuredPages[cursor] ??
            const NotificationPage(items: [], nextCursor: null),
      );
    }
    final rows = rowsByUser[fence.userId] ?? const <AppNotification>[];
    return right(
      NotificationPage(
        items: List.unmodifiable(rows),
        nextCursor: rows.isEmpty ? null : 'cursor-${rows.last.id}',
      ),
    );
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

  /// The inbox screen never asks for this: the list it already holds is the
  /// source of its unread count.
  @override
  Future<Either<Failure, int>> unreadCount({
    required NowaveSessionFence fence,
  }) async {
    calls.add('unreadCount');
    return right(0);
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

  test('loads older pages until an empty page marks the inbox end', () async {
    final firstPage = NotificationPage(
      items: [_notification(id: 'newest')],
      nextCursor: 'cursor-newest',
    );
    final secondPage = NotificationPage(
      items: [_notification(id: 'older')],
      nextCursor: 'cursor-older',
    );
    await pumpCubit(
      configure: (repository) {
        repository.pagesByCursor['user-a'] = {
          null: firstPage,
          'cursor-newest': secondPage,
          'cursor-older': const NotificationPage(items: [], nextCursor: null),
        };
      },
    );

    expect(_loaded(cubit).items.map((item) => item.id), ['newest']);
    expect(_loaded(cubit).hasMore, isTrue);

    await cubit.loadMore();

    expect(_loaded(cubit).items.map((item) => item.id), ['newest', 'older']);
    expect(_loaded(cubit).hasMore, isTrue);
    expect(repository.cursors, [null, 'cursor-newest']);

    await cubit.loadMore();

    expect(_loaded(cubit).items.map((item) => item.id), ['newest', 'older']);
    expect(_loaded(cubit).hasMore, isFalse);
    expect(_loaded(cubit).paginationUnavailable, isFalse);
    expect(repository.cursors, [null, 'cursor-newest', 'cursor-older']);
  });

  test('refresh replaces appended history with the newest page', () async {
    await pumpCubit(
      configure: (repository) {
        repository.pagesByCursor['user-a'] = {
          null: NotificationPage(
            items: [_notification(id: 'newest')],
            nextCursor: 'cursor-newest',
          ),
          'cursor-newest': NotificationPage(
            items: [_notification(id: 'older')],
            nextCursor: 'cursor-older',
          ),
        };
      },
    );
    await cubit.loadMore();
    expect(_loaded(cubit).items.map((item) => item.id), ['newest', 'older']);

    repository.pagesByCursor['user-a'] = {
      null: NotificationPage(
        items: [_notification(id: 'refreshed')],
        nextCursor: 'cursor-refreshed',
      ),
    };
    await cubit.load();

    expect(_loaded(cubit).items.map((item) => item.id), ['refreshed']);
    expect(_loaded(cubit).hasMore, isTrue);
    expect(repository.cursors, [null, 'cursor-newest', null]);
  });

  test(
    'does not append a repeated first page from a cursor-blind server',
    () async {
      await pumpCubit(
        rows: {
          'user-a': [_notification(id: 'newest'), _notification(id: 'older')],
        },
      );

      await cubit.loadMore();

      expect(_loaded(cubit).items.map((item) => item.id), ['newest', 'older']);
      expect(_loaded(cubit).hasMore, isFalse);
      expect(_loaded(cubit).paginationUnavailable, isTrue);
    },
  );

  test(
    'a cursor rejection stops retrying without dropping loaded rows',
    () async {
      await pumpCubit(
        rows: {
          'user-a': [_notification(id: 'newest')],
        },
      );
      repository.listFailure = const Failure(
        'The server rejected notification pagination.',
        kind: FailureKind.server,
        code: notificationCursorUnavailableFailureCode,
      );

      await cubit.loadMore();

      expect(_loaded(cubit).items.single.id, 'newest');
      expect(_loaded(cubit).hasMore, isFalse);
      expect(_loaded(cubit).paginationUnavailable, isTrue);
      expect(_loaded(cubit).loadMoreFailure, isNull);
    },
  );

  test('a failed older-page request keeps its cursor for retry', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification(id: 'newest')],
      },
    );
    repository.listFailure = _offline;
    repository.pagesByCursor['user-a'] = {
      'cursor-newest': NotificationPage(
        items: [_notification(id: 'older')],
        nextCursor: 'cursor-older',
      ),
    };

    await cubit.loadMore();

    expect(_loaded(cubit).items.single.id, 'newest');
    expect(_loaded(cubit).loadMoreFailure?.code, 'network.unavailable');
    expect(_loaded(cubit).hasMore, isTrue);

    repository.listFailure = null;
    await cubit.loadMore();

    expect(_loaded(cubit).items.map((item) => item.id), ['newest', 'older']);
    expect(_loaded(cubit).loadMoreFailure, isNull);
    expect(repository.cursors, [null, 'cursor-newest', 'cursor-newest']);
  });

  test('an older-page response from a previous account is dropped', () async {
    await pumpCubit(
      rows: {
        'user-a': [_notification(id: 'row-a')],
        'user-b': [_notification(id: 'row-b')],
      },
    );
    repository.gateUser = 'user-a';

    final stalePage = cubit.loadMore();
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(cubit).isLoadingMore, isTrue);

    identity.replace('user-b');
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(cubit).items.single.id, 'row-b');

    repository.gate.complete();
    await stalePage;

    expect(_loaded(cubit).items.single.id, 'row-b');
    expect(repository.fences.last.userId, 'user-b');
    expect(repository.cursors, [null, 'cursor-row-a', null]);
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
