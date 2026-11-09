import 'package:belog/core/error/failures.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/features/messages/presentation/pages/message_inbox_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/message_fakes.dart';

class _Harness {
  _Harness({
    List<Conversation> conversations = const [],
    String? startWith,
    bool signedIn = true,
    String? defaultName = '读者乙',
    Failure? conversationsFailure,
  }) : startWith = startWith {
    repository.conversationsResult = conversations;
    // Before the cubit exists: its constructor reads immediately.
    repository.conversationsFailure = conversationsFailure;
    names.names.clear();
    if (defaultName != null) names.names['user-b'] = defaultName;
    identity = MessageTestIdentity();
    if (!signedIn) {
      identity
        ..userId = null
        ..token = null;
    }
    cubit = MessageInboxCubit(
      repository: repository,
      identity: identity,
      names: names,
    );
    router = GoRouter(
      initialLocation: '/profile/messages',
      routes: [
        GoRoute(
          path: '/profile/messages',
          builder: (_, _) =>
              MessageInboxPage(cubit: cubit, startWith: startWith),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) =>
                  Scaffold(body: Text('thread: ${state.pathParameters['id']}')),
            ),
          ],
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
      ],
    );
  }

  final FakeMessageRepository repository = FakeMessageRepository();
  final FakeParticipantNames names = FakeParticipantNames();
  final String? startWith;
  late final MessageTestIdentity identity;
  late final MessageInboxCubit cubit;
  late final GoRouter router;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
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
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    router.dispose();
    await cubit.close();
    await identity.close();
  }
}

void main() {
  testWidgets('lists conversations with a name, a preview and an unread pill', (
    tester,
  ) async {
    final harness = _Harness(
      conversations: [
        testConversation(
          unreadCount: 2,
          lastMessage: testMessage(body: '最近一条私信'),
        ),
      ],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text('读者乙'), findsOneWidget);
    expect(find.text('最近一条私信'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(l10n.messagesUnreadCount(2)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a conversation with no unread messages has no pill', (
    tester,
  ) async {
    final harness = _Harness(conversations: [testConversation()]);
    addTearDown(harness.dispose);
    await harness.pump(tester);

    expect(find.text('0'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets(
    'a non-creator is not offered permanent deletion',
    (tester) async {
      final harness = _Harness(
        conversations: [
          testConversation(participants: ['user-b', 'user-a']),
        ],
      );
      addTearDown(harness.dispose);
      await harness.pump(tester);
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(find.byTooltip(l10n.messagesActions), findsNothing);
    },
  );

  testWidgets('a name the server did not give is stated, not faked', (
    tester,
  ) async {
    final harness = _Harness(
      conversations: [testConversation()],
      defaultName: null,
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesUnknownParticipant), findsOneWidget);
    // The raw id is never printed as if it were a name.
    expect(find.text('user-b'), findsNothing);
  });

  testWidgets('an empty inbox explains how a conversation starts', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesEmptyBody), findsOneWidget);
  });

  testWidgets('a failed read offers a retry that asks again', (tester) async {
    final harness = _Harness(conversationsFailure: testOffline);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    final before = harness.repository.calls.length;

    await tester.tap(find.text(l10n.actionRetry));
    await tester.pumpAndSettle();

    expect(harness.repository.calls.length, before + 1);
  });

  testWidgets('tapping a conversation opens its thread', (tester) async {
    final harness = _Harness(
      conversations: [testConversation(id: 'conversation-7')],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await tester.tap(find.text('读者乙'));
    await tester.pumpAndSettle();

    expect(find.text('thread: conversation-7'), findsOneWidget);
  });

  testWidgets('cancel keeps a destructive conversation delete untouched', (
    tester,
  ) async {
    final harness = _Harness(conversations: [testConversation()]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.messagesActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messagesDeleteAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.messagesDeleteTitle), findsOneWidget);
    expect(find.text(l10n.messagesDeleteBody), findsOneWidget);
    await tester.tap(find.text(l10n.actionCancel));
    await tester.pumpAndSettle();

    expect(harness.repository.deletedConversationIds, isEmpty);
    expect(find.text('读者乙'), findsOneWidget);
  });

  testWidgets('confirmed delete removes the row after the server agrees', (
    tester,
  ) async {
    final harness = _Harness(conversations: [testConversation()]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.messagesActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messagesDeleteAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionDelete));
    await tester.pumpAndSettle();

    expect(harness.repository.deletedConversationIds, ['conversation-1']);
    expect(find.text('读者乙'), findsNothing);
    expect(find.text(l10n.messagesDeleted), findsOneWidget);
  });

  testWidgets('an unknown delete outcome keeps the row and advises refresh', (
    tester,
  ) async {
    final harness = _Harness(conversations: [testConversation()]);
    harness.repository.deleteConversationFailure = testOffline;
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byTooltip(l10n.messagesActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messagesDeleteAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.actionDelete));
    await tester.pumpAndSettle();

    expect(find.text('读者乙'), findsOneWidget);
    expect(find.text(l10n.messagesDeleteOutcomeUnknown), findsOneWidget);
    expect(harness.repository.deletedConversationIds, ['conversation-1']);
  });

  testWidgets('an author page recipient with a thread goes straight there', (
    tester,
  ) async {
    final harness = _Harness(
      conversations: [testConversation(id: 'existing')],
      startWith: 'user-b',
    );
    addTearDown(harness.dispose);
    await harness.pump(tester);

    // The inbox is the entry point, not the destination: an existing
    // conversation is opened instead of creating a second one.
    expect(find.text('thread: existing'), findsOneWidget);
    expect(harness.repository.startRequests, isEmpty);
  });

  testWidgets('an author page recipient without a thread offers to start one', (
    tester,
  ) async {
    final harness = _Harness(startWith: 'user-b');
    harness.repository.startResult = testConversation(id: 'created');
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l10n.messagesStartTitle('读者乙')), findsOneWidget);

    await tester.tap(find.text(l10n.messagesStart).last);
    await tester.pumpAndSettle();

    expect(harness.repository.startRequests.single.recipient, 'user-b');
    expect(harness.repository.startRequests.single.key, isNotEmpty);
    expect(find.text('thread: created'), findsOneWidget);
  });

  testWidgets('a start that fails says why and keeps the card', (tester) async {
    final harness = _Harness(startWith: 'user-b');
    harness.repository.startFailure = testOffline;
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(l10n.messagesStart).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.messagesStartTitle('读者乙')), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('signed out state points at sign-in', (tester) async {
    final harness = _Harness(signedIn: false);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(l10n.signIn));
    await tester.pumpAndSettle();

    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('the list fits 320px at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness(
      conversations: [
        testConversation(
          unreadCount: 12,
          lastMessage: testMessage(body: '一条很长的私信预览，用来确认窄屏与放大字体'),
        ),
      ],
    );
    addTearDown(harness.dispose);
    await harness.pump(tester, locale: const Locale('zh'), textScale: 2);

    expect(find.text('读者乙'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
