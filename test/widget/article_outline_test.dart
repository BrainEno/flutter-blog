import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/viewer/article_outline.dart';
import 'package:belog/features/blog/presentation/viewer/article_outline_sheet.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness, sampleUser;

/// A history that only keeps the positions the page reports.
class _History implements ReadingHistoryStore {
  final saved = <double>[];

  @override
  Future<void> record({required String userId, required Blog blog}) async {}

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async => const [];

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async => saved.add(progress);

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) async => null;

  @override
  Future<void> remove({required String userId, required String blogId}) async {}

  @override
  Future<void> clear({required String userId}) async {}
}

const _paragraph =
    'The city at night is a page nobody finished. Street lamps come on one '
    'by one and cut the road into tidy paragraphs, and we are the sentences '
    'inside them that keep being rewritten.';

String _section(String heading) =>
    '$heading\n\n${[for (var i = 0; i < 8; i++) _paragraph].join('\n\n')}';

BlogModel _article(String content) => BlogModel(
  id: 'long',
  title: 'An unfinished page',
  content: content,
  posterId: 'author',
  imageUrl: '',
  tags: const ['essay'],
  updatedAt: DateTime.utc(2025),
);

final _withHeadings = [
  _section('## Lamps'),
  _section('## Roads'),
  _section('### A side street'),
  _section('## Rewrites'),
].join('\n\n');

ScrollPosition _articleScroll(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.descendant(
          of: find.byType(BlogViewerPage),
          matching: find.byType(CustomScrollView),
        ),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position;
}

Finder _line(String title) => find.byKey(ValueKey('reader-outline-$title'));

/// The heading's text in the article itself, not its line in the sheet.
Finder _heading(String title) => find
    .descendant(
      of: find.byType(BlogViewerPage),
      matching: find.textContaining(title, findRichText: true),
    )
    .first;

void main() {
  group('ArticleOutline', () {
    List<md.Node> parse(String source) =>
        md.Document().parseLines(source.split('\n'));

    test('lists body headings in order, depth from the top level used', () {
      final outline = ArticleOutline.of(
        parse(
          '## One\n\ntext\n\n### One  *point*  one\n\n#### Deep\n\n'
          '##### Deeper\n\n## Two',
        ),
      );
      expect(
        [for (final entry in outline.entries) (entry.title, entry.depth)],
        [
          ('One', 0),
          ('One point one', 1),
          ('Deep', 2),
          ('Deeper', ArticleOutline.maxDepth),
          ('Two', 0),
        ],
      );
      expect(outline.worthShowing, isTrue);
    });

    test('skips empty headings and ones inside quotes or lists', () {
      final outline = ArticleOutline.of(
        parse('# \n\n> ## Quoted\n\n- item\n\n## Kept'),
      );
      expect([for (final entry in outline.entries) entry.title], ['Kept']);
    });

    test('too few headings are not worth a list', () {
      expect(ArticleOutline.of(parse('## A\n\n## B')).worthShowing, isFalse);
      expect(ArticleOutline.of(const []).entries, isEmpty);
    });
  });

  group('the reader', () {
    setUp(() => GetIt.instance.reset());

    Future<_History> open(WidgetTester tester, String content) async {
      final harness = Harness()..buildRouter(initialLocation: '/view/long');
      addTearDown(harness.dispose);
      final history = _History();
      GetIt.instance.registerSingleton<ReadingHistoryStore>(history);
      final article = _article(content);
      when(
        () => harness.remote.getBlogById(any()),
      ).thenAnswer((_) async => article);
      when(
        () => harness.remote.isBlogLikedByUser(any(), any()),
      ).thenAnswer((_) async => false);
      harness.appUserCubit.updateUser(sampleUser());
      await harness.pump(tester);
      await tester.pumpAndSettle();
      return history;
    }

    testWidgets('the contents list goes to the chosen section', (tester) async {
      final semantics = tester.ensureSemantics();
      final history = await open(tester, _withHeadings);

      await tester.tap(find.byKey(const ValueKey('reader-outline')));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleOutlineSheet), findsOneWidget);
      for (final title in ['Lamps', 'Roads', 'A side street', 'Rewrites']) {
        expect(_line(title), findsOneWidget);
      }
      // A nested heading sits a step in.
      expect(
        tester.getTopLeft(find.text('A side street')).dx,
        greaterThan(tester.getTopLeft(find.text('Roads')).dx),
      );
      // Near the top of the article the later sections are not marked.
      for (final title in ['Roads', 'A side street', 'Rewrites']) {
        expect(
          tester.getSemantics(_line(title)),
          isSemantics(isButton: true, isSelected: false),
        );
      }

      await tester.tap(_line('Rewrites'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleOutlineSheet), findsNothing);
      expect(_articleScroll(tester).pixels, greaterThan(0));
      // The heading now stands near the top of the page, under the bar.
      final top = tester
          .getTopLeft(
            find
                .descendant(
                  of: find.byType(BlogViewerPage),
                  matching: find.byType(CustomScrollView),
                )
                .first,
          )
          .dy;
      final headingTop = tester.getTopLeft(_heading('Rewrites')).dy;
      expect(headingTop - top, inInclusiveRange(0, 80));
      // The jump is a place in the text like any other.
      expect(history.saved, isNotEmpty);

      // Opened again, the list marks where the reader now is.
      await tester.tap(find.byKey(const ValueKey('reader-outline')));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_line('Rewrites')),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(_line('Lamps')),
        isSemantics(isButton: true, isSelected: false),
      );

      // Back up to the first section.
      await tester.tap(_line('Lamps'));
      await tester.pumpAndSettle();
      final lampsTop = tester.getTopLeft(_heading('Lamps')).dy;
      expect(lampsTop - top, inInclusiveRange(0, 80));
      semantics.dispose();
    });

    testWidgets('dismissing the list leaves the page where it was', (
      tester,
    ) async {
      await open(tester, _withHeadings);
      await tester.drag(find.byType(BlogViewerPage), const Offset(0, -600));
      await tester.pumpAndSettle();
      final before = _articleScroll(tester).pixels;

      await tester.tap(find.byKey(const ValueKey('reader-outline')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleOutlineSheet), findsNothing);
      expect(_articleScroll(tester).pixels, before);
    });

    testWidgets('an article with few headings has no contents button', (
      tester,
    ) async {
      await open(
        tester,
        [_section('## Lamps'), _section('## Roads')].join('\n\n'),
      );
      expect(find.byKey(const ValueKey('reader-outline')), findsNothing);
    });
  });

  testWidgets('a long list opens scrolled to the current section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final entries = ArticleOutline.of(
      md.Document().parseLines(
        [
          for (var i = 0; i < 30; i++) '## Part $i\n\ntext\n',
        ].join('\n').split('\n'),
      ),
    ).entries;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ArticleOutlineSheet.show(
                context,
                entries: entries,
                current: 25,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(entries, hasLength(30));
    final sheet = tester.getRect(find.byType(ArticleOutlineSheet));
    final current = tester.getRect(_line('Part 25'));
    expect(sheet.contains(current.center), isTrue);
  });
}
