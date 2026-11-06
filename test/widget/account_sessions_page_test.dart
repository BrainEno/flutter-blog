import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
import 'package:belog/features/user/domain/entities/session_revoke_outcome.dart';
import 'package:belog/features/user/domain/repositories/account_session_repository.dart';
import 'package:belog/features/user/presentation/pages/account_sessions_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

class _Repository implements AccountSessionRepository {
  final fences = <NowaveSessionFence>[];
  final pending = <Completer<Either<Failure, List<AccountSession>>>>[];
  final revoked = <({NowaveSessionFence fence, String id})>[];
  final revokePending = <Completer<Either<Failure, SessionRevokeOutcome>>>[];
  final othersFences = <NowaveSessionFence>[];
  final othersPending = <Completer<Either<Failure, int>>>[];

  @override
  Future<Either<Failure, List<AccountSession>>> listSessions(
    NowaveSessionFence fence,
  ) {
    fences.add(fence);
    final result = Completer<Either<Failure, List<AccountSession>>>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, SessionRevokeOutcome>> revokeSession(
    NowaveSessionFence fence,
    String sessionId,
  ) {
    revoked.add((fence: fence, id: sessionId));
    final result = Completer<Either<Failure, SessionRevokeOutcome>>();
    revokePending.add(result);
    return result.future;
  }

  @override
  Future<Either<Failure, int>> revokeOtherSessions(NowaveSessionFence fence) {
    othersFences.add(fence);
    final result = Completer<Either<Failure, int>>();
    othersPending.add(result);
    return result.future;
  }
}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
  updatedAt: DateTime.utc(2025),
);

AccountSession _session({
  String id = 'session-current',
  bool current = true,
  bool refreshed = true,
}) => AccountSession(
  id: id,
  createdAt: DateTime.utc(2026, 10, 30, 1),
  lastRefreshedAt: refreshed ? DateTime.utc(2026, 10, 31, 2, 30) : null,
  expiresAt: DateTime.utc(2026, 12, 30, 1),
  current: current,
);

class _Harness {
  final identity = _Identity();
  final repository = _Repository();
  final userCubit = AppUserCubit()..updateUser(_user('user-a'));

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      BlocProvider<AppUserCubit>.value(
        value: userCubit,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: AccountSessionsPage(repository: repository, identity: identity),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose() async {
    await userCubit.close();
    await identity.controller.close();
  }
}

void main() {
  testWidgets(
    'shows the server list as sessions, with current and refresh semantics',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(harness.repository.fences.single.userId, 'user-a');
      expect(harness.repository.fences.single.generation, 1);
      harness.repository.pending.single.complete(
        right([_session(), _session(current: false, refreshed: false)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('This session'), findsOneWidget);
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('Last refreshed: Not recorded'), findsOneWidget);
      expect(find.textContaining('up to 50 active sessions'), findsOneWidget);
      expect(
        find.textContaining('token renewal, not all activity'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Device names and locations are not provided'),
        findsOneWidget,
      );
      expect(find.textContaining('Signed in:'), findsNWidgets(2));
      expect(find.textContaining('Expires:'), findsNWidgets(2));
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh clears stale rows before an offline failure', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(right([_session()]));
    await tester.pumpAndSettle();
    expect(find.text('This session'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh sessions'));
    await tester.tap(find.byTooltip('Refresh sessions'));
    await tester.pump();
    expect(harness.repository.pending, hasLength(2));
    expect(find.text('This session'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    harness.repository.pending.last.complete(left(Failure.networkOffline()));
    await tester.pumpAndSettle();
    expect(find.text('This session'), findsNothing);
    expect(
      find.text('No network connection — check your settings'),
      findsOneWidget,
    );
  });

  testWidgets('empty and unknown-current responses are not confused', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(
      right([_session(current: false)]),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('current session was not identified'),
      findsOneWidget,
    );
    expect(find.text('This session'), findsNothing);
  });

  testWidgets('the server may legitimately return an empty list', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(right([]));
    await tester.pumpAndSettle();
    expect(find.text('No active sessions were returned.'), findsOneWidget);
    expect(
      find.textContaining('current session was not identified'),
      findsNothing,
    );
  });

  testWidgets(
    'an account switch hides A immediately and ignores a late result',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      harness.identity.replace('user-b');
      await tester.pump();
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      harness.userCubit.updateUser(_user('user-b'));
      harness.repository.pending.single.complete(right([_session()]));
      await tester.pumpAndSettle();
      expect(find.text('This session'), findsNothing);
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      expect(harness.repository.pending, hasLength(1));
    },
  );

  for (final replacement in <String?>['user-a', null]) {
    testWidgets(
      'loaded data is cleared on same-user login or sign-out: $replacement',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.pump(tester);
        harness.repository.pending.single.complete(right([_session()]));
        await tester.pumpAndSettle();
        expect(find.text('This session'), findsOneWidget);
        harness.identity.replace(replacement);
        await tester.pump();
        expect(find.text('This session'), findsNothing);
        expect(find.textContaining('Your sign-in changed'), findsOneWidget);
        expect(harness.repository.pending, hasLength(1));
      },
    );
  }

  testWidgets('a same-account profile update keeps the page', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(right([_session()]));
    await tester.pumpAndSettle();
    harness.userCubit.updateUser(_user('user-a'));
    await tester.pump();
    expect(find.text('This session'), findsOneWidget);
    expect(find.textContaining('Your sign-in changed'), findsNothing);
    expect(harness.repository.pending, hasLength(1));
  });

  testWidgets('app-user changes independently of identity also hide the list', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(right([_session()]));
    await tester.pumpAndSettle();
    harness.userCubit.updateUser(_user('user-b'));
    await tester.pump();
    expect(find.text('This session'), findsNothing);
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
  });

  testWidgets(
    'a transient app-user switch is not hidden by a quick switch back',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      harness.repository.pending.single.complete(right([_session()]));
      await tester.pumpAndSettle();
      harness.userCubit.updateUser(_user('user-b'));
      harness.userCubit.updateUser(_user('user-a'));
      await tester.pump();
      expect(find.text('This session'), findsNothing);
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
    },
  );

  testWidgets('missing or mismatched identity sends no request', (
    tester,
  ) async {
    final harness = _Harness();
    harness.identity.userId = 'user-b';
    addTearDown(harness.dispose);
    await harness.pump(tester);
    expect(harness.repository.pending, isEmpty);
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
  });

  testWidgets(
    'unavailable and offline errors are not shown as empty data; retry fetches again',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      harness.repository.pending.single.complete(
        left(
          const Failure(
            '不显示此原始文字',
            code: 'sessions.unavailable',
            kind: FailureKind.server,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This server does not provide the session list'),
        findsOneWidget,
      );
      expect(find.text('No active sessions were returned.'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(harness.repository.pending, hasLength(2));
      harness.repository.pending.last.complete(left(Failure.networkOffline()));
      await tester.pumpAndSettle();
      expect(
        find.text('No network connection — check your settings'),
        findsOneWidget,
      );
      expect(find.text('No active sessions were returned.'), findsNothing);
    },
  );

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets('supports $locale at 320px and 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _Harness();
      addTearDown(harness.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await harness.pump(tester, locale: locale, scale: 2);
        harness.repository.pending.single.complete(
          right([_session(), _session(current: false, refreshed: false)]),
        );
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        expect(find.text(l10n.accountSessionsTitle), findsOneWidget);
        expect(find.text(l10n.accountSessionsCurrent), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text(l10n.accountSessionsNeverRefreshed), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('only the other rows offer "End"; the current one does not', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(
      right([_session(), _session(id: 'session-other', current: false)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('End'), findsOneWidget);
    expect(find.text('End other sessions'), findsOneWidget);
  });

  testWidgets('ending one row asks first, then re-reads the list', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(
      right([_session(), _session(id: 'session-other', current: false)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(find.text('End this session?'), findsOneWidget);
    expect(
      find.textContaining('This device stays signed in'),
      findsOneWidget,
    );
    // Cancelling sends nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.repository.revoked, isEmpty);

    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End sessions'));
    await tester.pumpAndSettle();
    expect(harness.repository.revoked.single.id, 'session-other');
    expect(harness.repository.revoked.single.fence.userId, 'user-a');
    // In flight: the row says so and the bulk action is disabled.
    expect(find.text('Ending…'), findsOneWidget);
    final others = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'End other sessions'),
    );
    expect(others.onPressed, isNull);

    harness.repository.revokePending.single.complete(
      right(SessionRevokeOutcome.ended),
    );
    await tester.pump();
    await tester.pump();
    // The list is re-read rather than edited locally.
    expect(harness.repository.pending, hasLength(2));
    harness.repository.pending.last.complete(right([_session()]));
    await tester.pumpAndSettle();
    expect(find.text('That session was ended.'), findsOneWidget);
    expect(find.text('End'), findsNothing);
  });

  testWidgets('a session that is already gone is not reported as an error', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(
      right([_session(), _session(id: 'session-other', current: false)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End sessions'));
    await tester.pumpAndSettle();
    harness.repository.revokePending.single.complete(
      right(SessionRevokeOutcome.alreadyEnded),
    );
    await tester.pump();
    await tester.pump();
    harness.repository.pending.last.complete(right([_session()]));
    await tester.pumpAndSettle();

    expect(find.textContaining('already gone'), findsOneWidget);
    expect(find.text('That session was ended.'), findsNothing);
  });

  testWidgets('ending the others says how many went and warns when unknown', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(
      right([_session(), _session(id: 'session-other', current: false)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('End other sessions'));
    await tester.pumpAndSettle();
    expect(find.text('End every other session?'), findsOneWidget);
    expect(find.textContaining('This device stays signed in'), findsOneWidget);
    await tester.tap(find.text('End sessions'));
    await tester.pumpAndSettle();
    expect(harness.repository.othersFences.single.generation, 1);

    harness.repository.othersPending.single.complete(right(3));
    await tester.pump();
    await tester.pump();
    harness.repository.pending.last.complete(right([_session()]));
    await tester.pumpAndSettle();
    expect(find.text('Ended 3 other sessions.'), findsOneWidget);
  });

  testWidgets('without an identified current session the warning is honest', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    // No `current: true` row: the token may not name its own session, so the
    // server could end this device too.
    harness.repository.pending.single.complete(
      right([_session(id: 'session-other', current: false)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('End other sessions'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('may end this device too'),
      findsOneWidget,
    );
    expect(find.textContaining('This device stays signed in'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('an old deployment says so instead of failing silently', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.repository.pending.single.complete(
      right([_session(), _session(id: 'session-other', current: false)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('End other sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End sessions'));
    await tester.pumpAndSettle();
    harness.repository.othersPending.single.complete(
      left(
        const Failure(
          '不显示此原始文字',
          kind: FailureKind.server,
          code: 'sessions.revokeUnavailable',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    harness.repository.pending.last.complete(right([_session()]));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This server cannot end sessions'),
      findsOneWidget,
    );
    expect(find.textContaining('不显示此原始文字'), findsNothing);
  });
}
