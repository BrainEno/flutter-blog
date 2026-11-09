import 'dart:async';

import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/entities/notification_page.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
import 'package:belog/features/notifications/presentation/pages/notification_inbox_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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
}

class _Repository implements NotificationRepository {
  final queues = <Completer<Either<Failure, NotificationPage>>>[];
  final calls = <String>[];
  final cursors = <String?>[];
  List<AppNotification> rows = [];
  Failure? failure;

  @override
  Future<Either<Failure, NotificationPage>> list({
    required NowaveSessionFence fence,
    int limit = 50,
    String? cursor,
  }) {
    calls.add('list');
    cursors.add(cursor);
    final result = Completer<Either<Failure, NotificationPage>>();
    queues.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, AppNotification>> markRead(
    String id, {
    required NowaveSessionFence fence,
  }) async {
    calls.add('markRead:$id');
    final updated = rows
        .firstWhere((row) => row.id == id)
        .markedRead(DateTime.utc(2026, 11, 5, 7));
    rows = [
      for (final row in rows)
        if (row.id == id) updated else row,
    ];
    return right(updated);
  }

  @override
  Future<Either<Failure, int>> markAllRead({
    required NowaveSessionFence fence,
  }) async {
    calls.add('markAllRead');
    return right(rows.where((row) => !row.isRead).length);
  }

  /// The inbox counts its own page; the badge endpoint belongs to the profile.
  @override
  Future<Either<Failure, int>> unreadCount({
    required NowaveSessionFence fence,
  }) async {
    calls.add('unreadCount');
    return right(rows.where((row) => !row.isRead).length);
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
  purgesAt: kind == AppNotificationKind.articleDeleted
      ? DateTime.utc(2026, 12, 5)
      : null,
  conversationId: kind == AppNotificationKind.messageReceived
      ? 'conversation-1'
      : null,
);

class _Harness {
  _Harness({
    List<AppNotification> rows = const [],
    Failure? failure,
    bool signedIn = true,
  }) : repository = _Repository()
         ..rows = [...rows]
         ..failure = failure {
    identity = signedIn
        ? _Identity()
        : (_Identity()
            ..userId = null
            ..token = null);
    cubit = NotificationInboxCubit(repository: repository, identity: identity);
  }

  final _Repository repository;
  late final _Identity identity;
  late final NotificationInboxCubit cubit;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotificationInboxPage(cubit: cubit),
      ),
    );
    await tester.pump();
  }

  void settle([Either<Failure, NotificationPage>? result]) {
    final failure = repository.failure;
    final rows = List<AppNotification>.unmodifiable(repository.rows);
    final page = NotificationPage(
      items: rows,
      nextCursor: rows.isEmpty ? null : 'cursor-${rows.last.id}',
    );
    for (final queue in repository.queues) {
      if (queue.isCompleted) continue;
      queue.complete(
        result ?? (failure != null ? left(failure) : right(page)),
      );
    }
  }

  Future<void> dispose() async {
    await cubit.close();
    await identity.controller.close();
  }
}

void main() {
  testWidgets('reads once, then lists what happened newest first', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    expect(find.byType(NoWaveSkeletonList), findsOneWidget);
    expect(harness.repository.calls, ['list']);

    harness.repository.rows = [
      _notification(),
      _notification(
        id: 'notification-2',
        kind: AppNotificationKind.messageReceived,
      ),
      _notification(id: 'notification-3', kind: AppNotificationKind.unknown),
    ];
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.textContaining('removed with it'), findsOneWidget);
    expect(find.textContaining('private message'), findsOneWidget);
    expect(find.textContaining('new notification'), findsOneWidget);
    expect(find.text('3 unread among loaded notifications'), findsOneWidget);
    expect(find.text('Mark as read'), findsNWidgets(3));
    // No polling: opening the page is the only read.
    expect(harness.repository.calls, ['list']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese private-message notification offers its conversation', (
    tester,
  ) async {
    final harness = _Harness(
      rows: [_notification(kind: AppNotificationKind.messageReceived)],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester, locale: const Locale('zh'));
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.text('收到一条新的私信'), findsOneWidget);
    expect(find.text('打开会话'), findsOneWidget);
    expect(find.text('加载更早的通知'), findsOneWidget);
    expect(find.textContaining('暂不支持查看会话'), findsNothing);
  });

  testWidgets('loads older pages and stops when the server returns empty', (
    tester,
  ) async {
    final harness = _Harness(rows: [_notification(id: 'newest')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.text('Load older notifications'), findsOneWidget);
    await tester.tap(find.text('Load older notifications'));
    await tester.pump();
    expect(harness.repository.calls, ['list', 'list']);
    expect(harness.repository.cursors, [null, 'cursor-newest']);

    harness.repository.rows = [_notification(id: 'older')];
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.textContaining('removed with it'), findsNWidgets(2));
    expect(find.text('Load older notifications'), findsOneWidget);
    await tester.tap(find.text('Load older notifications'));
    await tester.pump();
    expect(harness.repository.cursors, [null, 'cursor-newest', 'cursor-older']);

    harness.repository.rows = [];
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.text('No older notifications.'), findsOneWidget);
    expect(find.text('Load older notifications'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server that ignores cursors does not append duplicate rows', (
    tester,
  ) async {
    final harness = _Harness(rows: [_notification(id: 'newest')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load older notifications'));
    await tester.pump();
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.textContaining('removed with it'), findsOneWidget);
    expect(
      find.text(
        'This server does not support loading older notifications yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('Load older notifications'), findsNothing);
    expect(harness.repository.cursors, [null, 'cursor-newest']);
  });

  testWidgets('a failed older-page request keeps rows and can be retried', (
    tester,
  ) async {
    final harness = _Harness(rows: [_notification(id: 'newest')]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load older notifications'));
    await tester.pump();
    harness.repository.failure = const Failure(
      '无法连接到网络，请检查网络设置',
      kind: FailureKind.network,
      code: 'network.unavailable',
    );
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.textContaining('removed with it'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    harness.repository.failure = null;
    harness.repository.rows = [_notification(id: 'older')];
    await tester.tap(find.text('Retry'));
    await tester.pump();
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.textContaining('removed with it'), findsNWidgets(2));
    expect(harness.repository.cursors, [
      null,
      'cursor-newest',
      'cursor-newest',
    ]);
  });

  testWidgets('marks one row read and says so', (tester) async {
    final harness = _Harness(
      rows: [
        _notification(),
        _notification(id: 'notification-2'),
      ],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as read').first);
    await tester.pumpAndSettle();

    expect(harness.repository.calls, contains('markRead:notification-1'));
    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.text('1 unread among loaded notifications'), findsOneWidget);
    expect(find.text('Marked as read'), findsOneWidget);
  });

  testWidgets('marks everything read and the summary disappears', (
    tester,
  ) async {
    final harness = _Harness(
      rows: [
        _notification(),
        _notification(id: 'notification-2'),
      ],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls.last, 'markAllRead');
    expect(find.textContaining('unread'), findsNothing);
    expect(find.text('Mark as read'), findsNothing);
    expect(find.text('All marked as read'), findsOneWidget);
  });

  testWidgets('an empty inbox explains that nothing is pushed', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle(
      right(const NotificationPage(items: [], nextCursor: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('does not push notifications'), findsOneWidget);
    expect(find.text('Mark as read'), findsNothing);
  });

  testWidgets('a failure offers a retry that refetches', (tester) async {
    final harness = _Harness(
      failure: const Failure(
        '无法连接到网络，请检查网络设置',
        kind: FailureKind.network,
        code: 'network.unavailable',
      ),
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Mark as read'), findsNothing);

    harness.repository.failure = null;
    harness.repository.rows = [_notification()];
    await tester.tap(find.text('Retry'));
    await tester.pump();
    harness.settle();
    await tester.pumpAndSettle();

    expect(harness.repository.calls, ['list', 'list']);
    expect(find.text('Mark as read'), findsOneWidget);
  });

  testWidgets('signed out, the inbox points at sign-in', (tester) async {
    final harness = _Harness(signedIn: false);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to see your notifications'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(harness.repository.calls, isEmpty);
  });
}
