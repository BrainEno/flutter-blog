import 'dart:async';

import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/presentation/blocs/publish_queue/publish_queue_cubit.dart';
import 'package:belog/features/blog/presentation/pages/publish_queue_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/publish_queue_fakes.dart';

class _Identity implements NowaveSessionIdentity {
  String? userId = 'user';
  final controller = StreamController<void>.broadcast(sync: true);

  @override
  String? get activeUserId => userId;

  @override
  String? get accessToken => userId == null ? null : 'synthetic-token';

  @override
  int get sessionGeneration => 1;

  @override
  Stream<void> get identityChanges => controller.stream;
}

void main() {
  late FakePublishQueueStore store;
  late _Identity identity;
  late PublishQueueCubit cubit;
  late GoRouter router;
  Object? pushedExtra;

  Future<void> pump(
    WidgetTester tester, {
    required List<PublishQueueEntry> rows,
  }) async {
    store = FakePublishQueueStore(rows: rows);
    identity = _Identity();
    cubit = PublishQueueCubit(
      store: store,
      drainer: FakePublishQueueDrainer(),
      identity: identity,
    );
    addTearDown(() async {
      await cubit.close();
      await identity.controller.close();
    });
    pushedExtra = null;
    router = GoRouter(
      initialLocation: '/profile/publish-queue',
      routes: [
        GoRoute(
          path: '/profile/publish-queue',
          builder: (context, state) => PublishQueuePage(cubit: cubit),
        ),
        GoRoute(
          path: '/profile/editor',
          builder: (context, state) {
            pushedExtra = state.extra;
            return const Scaffold(body: Text('editor stub'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('only a stopped entry offers continue editing', (tester) async {
    await pump(
      tester,
      rows: [
        queueEntry(id: 'stopped'),
        queueEntry(
          id: 'waiting',
          status: PublishQueueStatus.queued,
          attempts: 0,
          lastErrorCode: null,
        ),
      ],
    );

    expect(find.text('Continue editing'), findsOneWidget);
    expect(find.text('Retry'), findsNWidgets(2));
    expect(find.text('Remove'), findsNWidgets(2));
  });

  testWidgets('continue editing opens the editor with that entry', (
    tester,
  ) async {
    await pump(tester, rows: [queueEntry(id: 'stopped')]);

    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();

    expect(find.text('editor stub'), findsOneWidget);
    expect(pushedExtra, isA<PublishQueueEntry>());
    expect((pushedExtra! as PublishQueueEntry).id, 'stopped');
  });

  testWidgets('returning from the editor re-reads the queue', (tester) async {
    await pump(tester, rows: [queueEntry(id: 'stopped')]);
    final readsBefore = store.entriesCalls;

    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();
    // The editor may have retired the entry; this screen cannot know without
    // asking the store again.
    router.pop();
    await tester.pumpAndSettle();

    expect(store.entriesCalls, greaterThan(readsBefore));
    expect(find.text('Continue editing'), findsOneWidget);
  });
}
