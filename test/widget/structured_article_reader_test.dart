import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/read_aloud/structured_article_nodes.dart';
import 'package:belog/features/blog/presentation/widgets/article_cover.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import '../support/read_aloud_fakes.dart';
import '../support/structured_article_fixtures.dart';
import 'router_test.dart' show Harness;

Widget readerApp(
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

Iterable<TextSpan> spans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* spans(child);
  }
}

void main() {
  setUp(() => GetIt.instance.reset());

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'rich blocks render without speech on a small screen: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final model = BlogModel.fromNowaveArticle(structuredArticle());
          final nodes = structuredArticleNodes(model.document!, webBaseUrl: '');
          final document = ReadAloudDocument.fromNodes(model.title, nodes);
          await tester.pumpWidget(
            readerApp(
              MarkdownBody(
                markdown: model.content,
                readAloudDocument: document,
              ),
              locale: locale,
              scale: 2,
            ),
          );
          final l10n = lookupAppLocalizations(locale);
          expect(find.text(l10n.articleImageUnavailable), findsNWidgets(2));
          expect(find.text('First caption'), findsOneWidget);
          expect(find.text('Second caption'), findsOneWidget);
          expect(find.text('literal **asterisks**'), findsOneWidget);
          expect(find.text('Quoted words'), findsOneWidget);
          expect(find.text('— Author name'), findsOneWidget);
          expect(find.text('First item'), findsOneWidget);
          expect(find.text(' second item '), findsOneWidget);
          expect(find.text('dart'), findsOneWidget);
          expect(find.text('  a\n\n b  \n'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('First image alt')),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp('Second image alt')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('read-aloud highlights keep every inline mark and link', (
    tester,
  ) async {
    final model = BlogModel.fromNowaveArticle({
      'contentBlocksVersion': 1,
      'contentBlocks': [
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'gone next code',
          'inlines': [
            {
              'text': 'gone',
              'marks': ['bold', 'italic', 'underline', 'strikethrough'],
              'href': 'https://site.test/page',
            },
            {'text': ' next '},
            {
              'text': 'code',
              'marks': ['code', 'bold', 'italic', 'underline', 'strikethrough'],
              'href': 'https://site.test/code',
            },
          ],
        },
      ],
    });
    final doc = ReadAloudDocument.fromNodes(
      'Title',
      structuredArticleNodes(model.document!),
    );
    final engine = FakeSpeechEngine();
    final controller = ReadAloudController(
      document: doc,
      coordinator: SpeechCoordinator(engine),
      preferences: FakeReadAloudPreferences(),
      fallbackLanguage: 'en',
    );
    await controller.initialize();
    addTearDown(() async {
      controller.dispose();
      await flushSpeech();
      await engine.close();
    });
    await tester.pumpWidget(
      readerApp(
        MarkdownBody(
          markdown: model.content,
          readAloudDocument: doc,
          readAloudController: controller,
        ),
      ),
    );
    controller.togglePlayback();
    await tester.pump();
    engine.event(engine.calls.last.id, SpeechEventType.completed);
    await tester.pump();
    expect(engine.calls.last.text, 'gone next code');
    engine.event(engine.calls.last.id, SpeechEventType.range, start: 0, end: 4);
    await tester.pump();
    final paragraph = tester.widget<Text>(find.textContaining('gone').first);
    final paragraphSpans = spans(paragraph.textSpan!).toList();
    expect(
      paragraphSpans.any(
        (s) =>
            s.style?.fontWeight == FontWeight.bold &&
            s.style?.fontStyle == FontStyle.italic,
      ),
      isTrue,
    );
    final highlighted = paragraphSpans.singleWhere((s) => s.text == 'gone');
    expect(highlighted.recognizer, isNotNull);
    expect(
      highlighted.style?.decoration,
      TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );

    engine.event(
      engine.calls.last.id,
      SpeechEventType.range,
      start: 10,
      end: 14,
    );
    await tester.pump();
    final code = tester.widget<Text>(find.text('code'));
    expect(code.style?.fontWeight, FontWeight.bold);
    expect(code.style?.fontStyle, FontStyle.italic);
    expect(
      code.style?.decoration,
      TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );
    final highlightedCode = spans(
      code.textSpan!,
    ).singleWhere((s) => s.text == 'code');
    expect(
      highlightedCode.style?.decoration,
      TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'viewer uses structured body passed by cards without speech services',
    (tester) async {
      final harness = Harness()..buildRouter();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      await tester.pumpAndSettle();
      final model = BlogModel.fromNowaveArticle(structuredArticle());
      harness.router!.push('/view/structured', extra: model);
      await tester.pumpAndSettle();
      expect(find.text('First caption'), findsOneWidget);
      expect(find.text('Second caption'), findsOneWidget);
      expect(find.text('literal **asterisks**'), findsOneWidget);
      expect(
        find.byType(ArticleCover),
        findsNothing,
      ); // Images stay in the body.
      verifyNever(() => harness.remote.getBlogById('structured'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'viewer warns on unknown version, without pretending full text: $locale',
      (tester) async {
        final harness = Harness()..buildRouter(initialLocation: '/view/abc');
        addTearDown(harness.dispose);
        when(() => harness.remote.getBlogById('abc')).thenAnswer(
          (_) async => BlogModel.fromNowaveArticle({
            'id': 'id',
            'slug': 'abc',
            'title': 'Unknown article',
            'contentBlocksVersion': 99,
            'contentBlocks': [
              {'id': 'p', 'type': 'paragraph', 'text': 'Some fallback'},
              {'id': 'x', 'type': 'future-block', 'content': 'not rendered'},
            ],
          }),
        );
        await harness.pump(tester, locale: locale);
        await tester.pumpAndSettle();
        expect(
          find.text(lookupAppLocalizations(locale).articleUnsupportedDocument),
          findsOneWidget,
        );
        expect(find.text('Some fallback'), findsOneWidget);
        expect(find.text('not rendered'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
