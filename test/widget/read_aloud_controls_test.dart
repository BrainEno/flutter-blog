import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controls.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/read_aloud_fakes.dart';

Widget app(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.lightThemeMode,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

ReadAloudController readerFor(
  FakeSpeechEngine engine,
  FakeReadAloudPreferences prefs, {
  String body = 'Hello **bold** and `code` world.',
}) => ReadAloudController(
  document: ReadAloudDocument.parse('Title', body),
  coordinator: SpeechCoordinator(engine),
  preferences: prefs,
  fallbackLanguage: 'en',
);

bool hasUnderline(InlineSpan span, String value) {
  if (span is! TextSpan) return false;
  if (span.text == value &&
      span.style?.decoration == TextDecoration.underline) {
    return true;
  }
  return span.children?.any((child) => hasUnderline(child, value)) ?? false;
}

Iterable<TextSpan> leaves(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.text?.isNotEmpty == true) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* leaves(child);
  }
}

void main() {
  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'localized controls work with large text and accessibility: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        addTearDown(semantics.dispose);
        final engine = FakeSpeechEngine();
        final prefs = FakeReadAloudPreferences();
        final reader = readerFor(engine, prefs);
        await reader.initialize();
        addTearDown(() async {
          reader.dispose();
          await flushSpeech();
          await engine.close();
        });
        await tester.pumpWidget(
          app(ReadAloudControls(controller: reader), locale: locale, scale: 2),
        );
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        expect(find.text(l10n.readAloudListen), findsOneWidget);
        expect(find.text(l10n.readAloudFollow), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.readAloudSeek), findsWidgets);
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('read-aloud-seek')),
        );
        expect(slider.onChanged, isNull);
        await tester.tap(find.byKey(const ValueKey('read-aloud-play')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.readAloudPause), findsOneWidget);
        expect(find.byTooltip(l10n.readAloudStop), findsOneWidget);
        expect(engine.calls.single.text, 'Title');
        await tester.tap(find.byKey(const ValueKey('read-aloud-play')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.readAloudResume), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('read-aloud-follow')));
        await tester.pumpAndSettle();
        expect(prefs.follow, isFalse);
        await tester.tap(find.byTooltip(l10n.readAloudStop));
        await tester.pumpAndSettle();
        expect(find.text(l10n.readAloudStopped), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'all six speeds apply immediately and seeking previews before commit',
    (tester) async {
      final engine = FakeSpeechEngine();
      final reader = readerFor(engine, FakeReadAloudPreferences());
      await reader.initialize();
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await tester.pumpWidget(app(ReadAloudControls(controller: reader)));
      await tester.tap(find.byKey(const ValueKey('read-aloud-play')));
      await tester.pumpAndSettle();
      final old = engine.calls.last;
      await tester.tap(find.byKey(const ValueKey('read-aloud-speed')));
      await tester.pumpAndSettle();
      for (final label in ['0.5×', '0.75×', '1×', '1.25×', '1.5×', '2×']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('1.5×').last);
      await tester.pumpAndSettle();
      expect(engine.calls.last.rate, 1.5);
      expect(engine.calls.last.id, isNot(old.id));

      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('read-aloud-seek')),
      );
      final calls = engine.calls.length;
      slider.onChangeStart!(reader.progress);
      slider.onChanged!(0.7);
      await tester.pump();
      expect(reader.progress, 0.7);
      expect(engine.calls, hasLength(calls));
      slider.onChangeEnd!(0.7);
      await tester.pumpAndSettle();
      expect(engine.calls.length, greaterThan(calls));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling a slider pointer restores the real position without seeking',
    (tester) async {
      final engine = FakeSpeechEngine();
      final reader = readerFor(engine, FakeReadAloudPreferences());
      await reader.initialize();
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await tester.pumpWidget(app(ReadAloudControls(controller: reader)));
      await tester.tap(find.byKey(const ValueKey('read-aloud-play')));
      await tester.pumpAndSettle();
      final calls = engine.calls.length;
      final original = reader.progress;
      final slider = find.byKey(const ValueKey('read-aloud-seek'));
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(reader.progress, original);
      expect(engine.calls, hasLength(calls));
    },
  );

  testWidgets('word and code highlights keep Markdown text and styles intact', (
    tester,
  ) async {
    final engine = FakeSpeechEngine();
    final reader = readerFor(engine, FakeReadAloudPreferences());
    await reader.initialize();
    addTearDown(() async {
      reader.dispose();
      await flushSpeech();
      await engine.close();
    });
    await tester.pumpWidget(
      app(
        MarkdownBody(
          markdown: 'Hello **bold** and `code` world.',
          readAloudDocument: reader.document,
          readAloudController: reader,
        ),
      ),
    );
    reader.togglePlayback();
    await tester.pump();
    engine.event(engine.calls.last.id, SpeechEventType.completed);
    await tester.pump();
    final body = engine.calls.last;
    expect(body.text, 'Hello bold and code world.');
    engine.event(body.id, SpeechEventType.range, start: 6, end: 10);
    await tester.pump();
    final paragraph = tester.widget<Text>(find.textContaining('Hello').first);
    expect(paragraph.textSpan!.toPlainText(), contains('bold'));
    expect(hasUnderline(paragraph.textSpan!, 'bold'), isTrue);
    engine.event(body.id, SpeechEventType.range, start: 15, end: 19);
    await tester.pump();
    final code = tester.widget<Text>(find.text('code'));
    expect(hasUnderline(code.textSpan!, 'code'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'highlighting reuses clickable link recognizers on each text leaf',
    (tester) async {
      final engine = FakeSpeechEngine();
      const source = 'See [link](https://example.invalid) here.';
      final reader = readerFor(
        engine,
        FakeReadAloudPreferences(),
        body: source,
      );
      await reader.initialize();
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await tester.pumpWidget(
        app(
          MarkdownBody(
            markdown: source,
            readAloudDocument: reader.document,
            readAloudController: reader,
          ),
        ),
      );
      reader.togglePlayback();
      await tester.pump();
      engine.event(engine.calls.last.id, SpeechEventType.completed);
      await tester.pump();
      Text paragraph() => tester.widget<Text>(find.textContaining('See').first);
      final before = leaves(
        paragraph().textSpan!,
      ).singleWhere((leaf) => leaf.text == 'link').recognizer;
      expect(before, isNotNull);
      engine.event(
        engine.calls.last.id,
        SpeechEventType.range,
        start: 5,
        end: 7,
      );
      await tester.pump();
      final linkedLeaves = leaves(
        paragraph().textSpan!,
      ).where((leaf) => leaf.recognizer != null).toList();
      expect(linkedLeaves.map((leaf) => leaf.text).join(), 'link');
      expect(
        linkedLeaves.every((leaf) => identical(leaf.recognizer, before)),
        isTrue,
      );
    },
  );

  testWidgets(
    'empty or unsupported articles hide the entry; errors are visible',
    (tester) async {
      final engine = FakeSpeechEngine()..failSpeak = true;
      final reader = readerFor(engine, FakeReadAloudPreferences());
      await reader.initialize();
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await tester.pumpWidget(app(ReadAloudControls(controller: reader)));
      await tester.tap(find.byKey(const ValueKey('read-aloud-play')));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to read aloud. Check your device voice settings.'),
        findsOneWidget,
      );
      final empty = readerFor(engine, FakeReadAloudPreferences(), body: '');
      await empty.initialize();
      await tester.pumpWidget(app(ReadAloudControls(controller: empty)));
      expect(find.byKey(const ValueKey('read-aloud-controls')), findsNothing);
      empty.dispose();
    },
  );
}
