import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import '../support/read_aloud_fakes.dart';
import 'router_test.dart' show Harness;

void installSpeech(FakeSpeechEngine engine) {
  GetIt.instance.registerSingleton<SpeechCoordinator>(
    SpeechCoordinator(engine),
  );
  GetIt.instance.registerSingleton<ReadAloudPreferences>(
    FakeReadAloudPreferences(),
  );
}

Future<void> startPlayback(WidgetTester tester) async {
  final play = find.byKey(const ValueKey('read-aloud-play'));
  await tester.ensureVisible(play);
  await tester.pumpAndSettle();
  await tester.tap(play);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GetIt.instance.reset());

  testWidgets(
    'switching retained tabs stops the old reader and does not resume it',
    (tester) async {
      final harness = Harness()..buildRouter(initialLocation: '/view/abc');
      final engine = FakeSpeechEngine();
      installSpeech(engine);
      addTearDown(() async {
        await harness.dispose();
        await engine.close();
      });
      await harness.pump(tester);
      await tester.pumpAndSettle();
      await startPlayback(tester);
      expect(engine.calls.single.text, '深链文章');
      final before = engine.stopCount;
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      expect(engine.stopCount, greaterThan(before));
      engine.event(engine.calls.single.id, SpeechEventType.completed);
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(find.byType(BlogViewerPage), findsOneWidget);
      expect(find.text('朗读文章'), findsOneWidget);
      expect(engine.calls, hasLength(1));
    },
  );

  testWidgets(
    'page push, root login and background stop playback; dropdown does not',
    (tester) async {
      final harness = Harness()..buildRouter(initialLocation: '/view/abc');
      final engine = FakeSpeechEngine();
      installSpeech(engine);
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await harness.dispose();
        await engine.close();
      });
      await harness.pump(tester);
      await tester.pumpAndSettle();
      await startPlayback(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('read-aloud-speed')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('read-aloud-speed')));
      await tester.pumpAndSettle();
      expect(find.text('暂停'), findsOneWidget); // transient popup is not a page
      await tester.tap(find.text('1.25×').last);
      await tester.pumpAndSettle();
      expect(engine.calls.last.rate, 1.25);

      final beforePage = engine.stopCount;
      harness.router!.push('/author/author');
      await tester.pumpAndSettle();
      expect(engine.stopCount, greaterThan(beforePage));
      harness.router!.pop();
      await tester.pumpAndSettle();
      await startPlayback(tester);
      final beforeBackground = engine.stopCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(engine.stopCount, greaterThan(beforeBackground));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await startPlayback(tester);
      final beforeRoot = engine.stopCount;
      harness.router!.push('/login');
      await tester.pumpAndSettle();
      expect(engine.stopCount, greaterThan(beforeRoot));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'following advances through a long paragraph, not just to its beginning',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = Harness()..buildRouter(initialLocation: '/view/abc');
      when(() => harness.remote.getBlogById('abc')).thenAnswer(
        (_) async => BlogModel(
          id: 'abc',
          title: '长文章',
          content: '字' * 1200,
          posterId: 'author',
          imageUrl: '',
          tags: const [],
          updatedAt: DateTime.utc(2026),
        ),
      );
      final engine = FakeSpeechEngine();
      installSpeech(engine);
      addTearDown(() async {
        await harness.dispose();
        await engine.close();
      });
      await harness.pump(tester);
      await tester.pumpAndSettle();
      await startPlayback(tester);
      engine.event(
        engine.calls.last.id,
        SpeechEventType.completed,
      ); // title -> body
      await tester.pumpAndSettle();
      final view = tester.widget<CustomScrollView>(
        find
            .descendant(
              of: find.byType(BlogViewerPage),
              matching: find.byType(CustomScrollView),
            )
            .first,
      );
      final before = view.controller!.offset;
      for (var i = 0; i < 3; i++) {
        engine.event(engine.calls.last.id, SpeechEventType.completed);
        await tester.pumpAndSettle();
      }
      expect(view.controller!.offset, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );
}
