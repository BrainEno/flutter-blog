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
import 'package:go_router/go_router.dart';

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
  Completer<void>? markGate;
  Completer<void>? markAllGate;

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
    if (markGate case final gate?) await gate.future;
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
    if (markAllGate case final gate?) await gate.future;
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
  String? articleSlug,
  NotificationArticleLocale? articleLocale,
  String? followerId,
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
  articleSlug: articleSlug,
  articleLocale: articleLocale,
  followerId: followerId,
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
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
      queue.complete(result ?? (failure != null ? left(failure) : right(page)));
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

  testWidgets(
    'new event types have localized descriptions and stay individually markable',
    (tester) async {
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        final harness = _Harness(
          rows: [
            _notification(
              id: 'comment',
              kind: AppNotificationKind.articleCommented,
            ),
            _notification(
              id: 'reply',
              kind: AppNotificationKind.commentReplied,
            ),
            _notification(id: 'like', kind: AppNotificationKind.articleLiked),
            _notification(id: 'follow', kind: AppNotificationKind.userFollowed),
          ],
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.pump(tester, locale: locale);
        harness.settle();
        await tester.pumpAndSettle();
        final labels = lookupAppLocalizations(locale);
        expect(find.text(labels.notificationCommented), findsOneWidget);
        expect(find.text(labels.notificationReply), findsOneWidget);
        expect(find.text(labels.notificationLiked), findsOneWidget);
        expect(find.text(labels.notificationFollowed), findsOneWidget);
        expect(find.text(labels.notificationUnknown), findsNothing);
        expect(find.text(labels.notificationsOpenConversation), findsNothing);
        expect(find.text(labels.notificationsMarkRead), findsNWidgets(4));
        await tester.tap(find.text(labels.notificationsMarkRead).first);
        await tester.pumpAndSettle();
        expect(harness.repository.calls, ['list', 'markRead:comment']);
        expect(find.text(labels.notificationsMarkRead), findsNWidgets(3));
        expect(find.text(labels.notificationCommented), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'safe notification links open existing local routes without marking read',
    (tester) async {
      for (final entry in <AppNotificationKind, String>{
        AppNotificationKind.articleCommented: '/profile/view/work-1',
        AppNotificationKind.commentReplied: '/profile/view/work-1',
        AppNotificationKind.articleLiked: '/profile/view/work-1',
        AppNotificationKind.userFollowed: '/profile/author/user-1',
      }.entries) {
        final harness = _Harness(
          rows: [
            _notification(
              kind: entry.key,
              articleSlug: 'work-1',
              followerId: 'user-1',
            ),
          ],
        );
        addTearDown(harness.dispose);
        final router = GoRouter(
          initialLocation: '/profile/notifications',
          routes: [
            GoRoute(
              path: '/profile/notifications',
              builder: (_, _) => NotificationInboxPage(cubit: harness.cubit),
            ),
            GoRoute(
              path: '/profile/view/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('work:${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/profile/author/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('author:${state.pathParameters['id']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        );
        harness.settle();
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(const Locale('en'));
        final label = entry.key == AppNotificationKind.userFollowed
            ? l10n.notificationsOpenFollower
            : l10n.notificationsOpenArticleAddress;
        expect(
          find.text(l10n.notificationsAddressMayChange),
          entry.key == AppNotificationKind.userFollowed
              ? findsNothing
              : findsOneWidget,
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        final destination = entry.key == AppNotificationKind.userFollowed
            ? 'author:user-1'
            : 'work:work-1';
        expect(find.text(destination), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          entry.value,
        );
        expect(harness.repository.calls, ['list']);
        expect(harness.repository.rows.single.isRead, isFalse);
      }
    },
  );

  testWidgets('shows source edition and keeps it after marking read', (
    tester,
  ) async {
    for (final locale in [const Locale('en'), const Locale('zh')]) {
      for (final source in NotificationArticleLocale.values) {
        final harness = _Harness(
          rows: [
            _notification(
              kind: AppNotificationKind.commentReplied,
              articleSlug: 'work-1',
              articleLocale: source,
            ),
          ],
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.pump(tester, locale: locale);
        harness.settle();
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        final text = switch (source) {
          NotificationArticleLocale.english => l10n.notificationsSourceEnglish,
          NotificationArticleLocale.simplifiedChinese =>
            l10n.notificationsSourceSimplifiedChinese,
          NotificationArticleLocale.traditionalChinese =>
            l10n.notificationsSourceTraditionalChinese,
        };
        expect(find.text(text), findsOneWidget);
        await tester.ensureVisible(find.text(l10n.notificationsMarkRead));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.notificationsMarkRead));
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
        expect(harness.repository.rows.single.articleSourceLocale, source);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('legacy and invalid article notices have no edition label', (
    tester,
  ) async {
    final harness = _Harness(
      rows: [
        _notification(
          kind: AppNotificationKind.articleCommented,
          articleSlug: 'work-1',
        ),
        _notification(
          id: 'bad',
          kind: AppNotificationKind.commentReplied,
          articleSlug: '../bad',
          articleLocale: NotificationArticleLocale.english,
        ),
      ],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.notificationsSourceEnglish), findsNothing);
    expect(find.text(l10n.notificationsSourceSimplifiedChinese), findsNothing);
    expect(find.text(l10n.notificationsSourceTraditionalChinese), findsNothing);
    expect(find.text(l10n.notificationsOpenArticleAddress), findsOneWidget);
  });

  testWidgets('invalid destinations stay readable and never become buttons', (
    tester,
  ) async {
    final harness = _Harness(
      rows: [
        _notification(
          kind: AppNotificationKind.articleLiked,
          articleSlug: '../bad',
        ),
        _notification(
          id: 'follow',
          kind: AppNotificationKind.userFollowed,
          followerId: 'evil/route',
        ),
      ],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester, locale: const Locale('zh'));
    harness.settle();
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.text(l10n.notificationLiked), findsOneWidget);
    expect(find.text(l10n.notificationFollowed), findsOneWidget);
    expect(find.text(l10n.notificationsOpenArticleAddress), findsNothing);
    expect(find.text(l10n.notificationsOpenFollower), findsNothing);
    expect(find.text(l10n.notificationsMarkRead), findsNWidgets(2));
  });

  testWidgets(
    'old notification callback cannot open after account replacement',
    (tester) async {
      final harness = _Harness(
        rows: [
          _notification(
            kind: AppNotificationKind.articleLiked,
            articleSlug: 'work-1',
          ),
        ],
      );
      addTearDown(harness.dispose);
      final router = GoRouter(
        initialLocation: '/profile/notifications',
        routes: [
          GoRoute(
            path: '/profile/notifications',
            builder: (_, _) => NotificationInboxPage(cubit: harness.cubit),
          ),
          GoRoute(
            path: '/profile/view/:id',
            builder: (_, _) => const Scaffold(body: Text('unexpected work')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
      harness.settle();
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l10n.notificationsOpenArticleAddress),
      );
      harness.identity.userId = 'user-b';
      harness.identity.generation++;
      harness.identity.controller.add(null);
      button.onPressed!();
      await tester.pump();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/profile/notifications',
      );
      expect(find.text('unexpected work'), findsNothing);
      expect(harness.repository.calls, ['list', 'list']);
    },
  );

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

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    for (final kind in [
      AppNotificationKind.messageReceived,
      AppNotificationKind.articleLiked,
      AppNotificationKind.userFollowed,
      AppNotificationKind.articleDeleted,
    ]) {
      testWidgets(
        '320dp doubled text: $locale $kind keeps actions accessible',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final harness = _Harness(
            rows: [
              _notification(
                kind: kind,
                articleSlug: 'work-1',
                articleLocale: NotificationArticleLocale.traditionalChinese,
                followerId: 'user-1',
              ),
            ],
          );
          addTearDown(harness.dispose);
          await harness.pump(tester, locale: locale, textScale: 2);
          harness.settle();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final l10n = lookupAppLocalizations(locale);
          if (kind == AppNotificationKind.articleLiked) {
            expect(
              find.text(l10n.notificationsSourceTraditionalChinese),
              findsOneWidget,
            );
          }
          final openLabel = switch (kind) {
            AppNotificationKind.messageReceived =>
              l10n.notificationsOpenConversation,
            AppNotificationKind.articleLiked =>
              l10n.notificationsOpenArticleAddress,
            AppNotificationKind.userFollowed => l10n.notificationsOpenFollower,
            _ => null,
          };
          if (openLabel != null) {
            final open = find.widgetWithText(TextButton, openLabel);
            await tester.ensureVisible(open);
            await tester.pumpAndSettle();
            expect(tester.widget<TextButton>(open).onPressed, isNotNull);
            expect(tester.takeException(), isNull);
          }
          final mark = find.widgetWithText(
            TextButton,
            l10n.notificationsMarkRead,
          );
          await tester.ensureVisible(mark);
          await tester.pumpAndSettle();
          await tester.tap(mark);
          await tester.pumpAndSettle();
          expect(harness.repository.calls, ['list', 'markRead:notification-1']);
          expect(find.text(l10n.notificationsMarkRead), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final kind in [
      AppNotificationKind.messageReceived,
      AppNotificationKind.articleLiked,
    ]) {
      testWidgets('320dp doubled text: $locale $kind opens its route', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = _Harness(
          rows: [_notification(kind: kind, articleSlug: 'work-1')],
        );
        addTearDown(harness.dispose);
        final router = GoRouter(
          initialLocation: '/inbox',
          routes: [
            GoRoute(
              path: '/inbox',
              builder: (_, _) => NotificationInboxPage(cubit: harness.cubit),
            ),
            GoRoute(
              path: '/profile/view/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('work:${state.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/profile/messages/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('message:${state.pathParameters['id']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            locale: locale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        );
        await tester.pump();
        harness.settle();
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        final label = kind == AppNotificationKind.messageReceived
            ? l10n.notificationsOpenConversation
            : l10n.notificationsOpenArticleAddress;
        final button = find.widgetWithText(TextButton, label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.text(
            kind == AppNotificationKind.messageReceived
                ? 'message:conversation-1'
                : 'work:work-1',
          ),
          findsOneWidget,
        );
        expect(harness.repository.calls, ['list']);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320dp doubled text: $locale mark-all works from the summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _Harness(rows: [_notification()]);
      addTearDown(harness.dispose);
      await harness.pump(tester, locale: locale, textScale: 2);
      harness.settle();
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.notificationsLoadedUnreadCount(1)), findsOneWidget);
      final markAll = find.widgetWithText(
        TextButton,
        l10n.notificationsMarkAllRead,
      );
      await tester.ensureVisible(markAll);
      await tester.pumpAndSettle();
      await tester.tap(markAll);
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['list', 'markAllRead']);
      expect(find.text(l10n.notificationsMarkAllRead), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets(
    'pending single mark disables conflicting actions and stale callbacks',
    (tester) async {
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
      final labels = lookupAppLocalizations(const Locale('en'));
      final allFinder = find.widgetWithText(
        TextButton,
        labels.notificationsMarkAllRead,
      );
      final rowFinder = find.widgetWithText(
        TextButton,
        labels.notificationsMarkRead,
      );
      final staleAll = tester.widget<TextButton>(allFinder).onPressed!;
      final staleSecond = tester
          .widgetList<TextButton>(rowFinder)
          .last
          .onPressed!;
      final gate = harness.repository.markGate = Completer<void>();
      await tester.tap(rowFinder.first);
      await tester.pump();
      expect(tester.widget<TextButton>(allFinder).onPressed, isNull);
      expect(
        tester
            .widgetList<TextButton>(rowFinder)
            .every((button) => button.onPressed == null),
        isTrue,
      );
      staleAll();
      staleSecond();
      await tester.pump();
      expect(harness.repository.calls, ['list', 'markRead:notification-1']);
      expect(find.text(labels.notificationsAllRead), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(labels.notificationsMarkedRead), findsOneWidget);
      expect(tester.widget<TextButton>(allFinder).onPressed, isNotNull);
      expect(tester.widget<TextButton>(rowFinder).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending mark-all disables single actions and rejects stale callbacks',
    (tester) async {
      final harness = _Harness(rows: [_notification()]);
      addTearDown(harness.dispose);
      await harness.pump(tester);
      harness.settle();
      await tester.pumpAndSettle();
      final labels = lookupAppLocalizations(const Locale('en'));
      final rowFinder = find.widgetWithText(
        TextButton,
        labels.notificationsMarkRead,
      );
      final staleRow = tester.widget<TextButton>(rowFinder).onPressed!;
      final gate = harness.repository.markAllGate = Completer<void>();
      await tester.tap(
        find.widgetWithText(TextButton, labels.notificationsMarkAllRead),
      );
      await tester.pump();
      expect(tester.widget<TextButton>(rowFinder).onPressed, isNull);
      staleRow();
      await tester.pump();
      expect(harness.repository.calls, ['list', 'markAllRead']);
      expect(find.text(labels.notificationsMarkedRead), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(labels.notificationsAllRead), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh disables row marking until it completes', (
    tester,
  ) async {
    final harness = _Harness(rows: [_notification()]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.settle();
    await tester.pumpAndSettle();
    final labels = lookupAppLocalizations(const Locale('en'));
    final rowFinder = find.widgetWithText(
      TextButton,
      labels.notificationsMarkRead,
    );
    final staleRow = tester.widget<TextButton>(rowFinder).onPressed!;
    final refreshing = harness.cubit.load(showLoading: false);
    await tester.pump();
    expect(tester.widget<TextButton>(rowFinder).onPressed, isNull);
    staleRow();
    await tester.pump();
    expect(harness.repository.calls, ['list', 'list']);
    expect(find.text(labels.notificationsMarkedRead), findsNothing);
    harness.settle();
    await tester.pump();
    await refreshing;
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(rowFinder).onPressed, isNotNull);
  });

  testWidgets(
    'old mark completion cannot show success after an account switch',
    (tester) async {
      final harness = _Harness(rows: [_notification()]);
      addTearDown(harness.dispose);
      await harness.pump(tester);
      harness.settle();
      await tester.pumpAndSettle();
      final gate = harness.repository.markGate = Completer<void>();
      final labels = lookupAppLocalizations(const Locale('en'));
      await tester.tap(
        find.widgetWithText(TextButton, labels.notificationsMarkRead),
      );
      await tester.pump();
      harness.identity.userId = 'user-b';
      harness.identity.generation++;
      harness.identity.controller.add(null);
      await tester.pump();
      harness.settle(
        right(const NotificationPage(items: [], nextCursor: null)),
      );
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(labels.notificationsMarkedRead), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    harness.settle(right(const NotificationPage(items: [], nextCursor: null)));
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
