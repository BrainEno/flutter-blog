import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit.dart';
import 'package:belog/features/messages/presentation/pages/message_thread_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/message_fakes.dart';

class _Harness {
  _Harness({String conversationId = 'conversation-1'})
    : conversationId = conversationId {
    repository.conversationResult = testConversation(unreadCount: 2);
    repository.messagesResult = [
      testMessage(id: 'message-1', senderId: 'user-b', body: '你好'),
      testMessage(id: 'message-2', senderId: 'user-a', body: '也你好'),
    ];
    identity = MessageTestIdentity();
    cubit = MessageThreadCubit(
      conversationId: conversationId,
      repository: repository,
      identity: identity,
      names: names,
    );
    router = GoRouter(
      initialLocation: '/profile/messages/$conversationId',
      routes: [
        GoRoute(
          path: '/profile/messages/:id',
          builder: (_, _) => MessageThreadPage(
            conversationId: this.conversationId,
            cubit: cubit,
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
      ],
    );
  }

  final String conversationId;
  final FakeMessageRepository repository = FakeMessageRepository();
  final FakeParticipantNames names = FakeParticipantNames();
  late final MessageTestIdentity identity;
  late final MessageThreadCubit cubit;
  late final GoRouter router;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    bool load = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightThemeMode,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    if (load) {
      await cubit.load();
      await tester.pumpAndSettle();
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> dispose() async {
    router.dispose();
    await cubit.close();
    await identity.close();
  }
}

void main() {
  testWidgets('shows both sides of the conversation oldest first', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    expect(find.text('你好'), findsOneWidget);
    expect(find.text('也你好'), findsOneWidget);
    // The other participant's name titles the page once it is resolved.
    expect(find.text('读者乙'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending stores the message and clears the composer', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.enterText(find.byType(TextField), '新的一条');
    await tester.tap(find.byTooltip(l10n.actionSend));
    await tester.pumpAndSettle();

    expect(harness.repository.sendRequests.single.body, '新的一条');
    expect(harness.repository.sendRequests.single.key, isNotEmpty);
    expect(find.text('新的一条'), findsOneWidget);
    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller?.text, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed send keeps the draft and says why', (tester) async {
    final harness = _Harness();
    harness.repository.sendFailure = testOffline;
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.enterText(find.byType(TextField), '发不出去');
    await tester.tap(find.byTooltip(l10n.actionSend));
    await tester.pumpAndSettle();

    expect(find.text('发不出去'), findsOneWidget);
    expect(find.text(l10n.messagesDraftKept), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '发不出去',
    );
  });

  testWidgets('marking read is an explained, explicit action', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesMarkReadHint), findsOneWidget);
    await tester.tap(find.text(l10n.messagesMarkRead));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, contains('markRead:conversation-1'));
    expect(find.text(l10n.messagesMarkedRead), findsOneWidget);
    expect(find.text(l10n.messagesMarkReadHint), findsNothing);
  });

  testWidgets('nothing unread means no mark-read banner', (tester) async {
    final harness = _Harness();
    harness.repository.conversationResult = testConversation(unreadCount: 0);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesMarkReadHint), findsNothing);
  });

  testWidgets('a missing conversation states it and offers no retry', (
    tester,
  ) async {
    final harness = _Harness();
    harness.repository.conversationResult = null;
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesMissing), findsOneWidget);
    expect(find.text(l10n.actionRetry), findsNothing);
  });

  testWidgets('a broken read offers a retry that reads again', (tester) async {
    final harness = _Harness();
    harness.repository.messagesFailure = testOffline;
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    final before = harness.repository.calls.length;

    await tester.tap(find.text(l10n.actionRetry));
    await tester.pumpAndSettle();

    expect(harness.repository.calls.length, greaterThan(before));
  });

  testWidgets('older messages load on request', (tester) async {
    final harness = _Harness();
    harness.repository.messagesResult = [
      for (var i = 0; i < MessageThreadCubit.pageLimit; i++)
        testMessage(id: 'message-$i', body: '消息 $i'),
    ];
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesLoadOlder), findsOneWidget);
    harness.repository.messagesResult = [
      testMessage(id: 'older-1', body: '更早的一条'),
    ];
    await tester.tap(find.text(l10n.messagesLoadOlder));
    await tester.pumpAndSettle();

    expect(harness.repository.beforeCursors.last, 'message-0');
    expect(find.text('更早的一条'), findsOneWidget);
    expect(find.text(l10n.messagesLoadOlder), findsNothing);
  });

  testWidgets('an empty thread says so instead of showing a blank page', (
    tester,
  ) async {
    final harness = _Harness();
    harness.repository.messagesResult = [];
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesThreadEmpty), findsOneWidget);
  });

  testWidgets('the thread fits 320px at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness();
    harness.repository.messagesResult = [
      testMessage(
        id: 'message-1',
        senderId: 'user-b',
        body: '一条很长的私信内容，用来确认窄屏与大字号下气泡不会溢出',
      ),
    ];
    addTearDown(harness.dispose);
    await harness.pump(tester, locale: const Locale('zh'), textScale: 2);

    expect(find.text('读者乙'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
