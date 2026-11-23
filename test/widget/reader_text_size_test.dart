import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/reader/reader_text_size.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_controller.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_sheet.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness, sampleUser;

/// Keeps the size in memory, and counts what it was asked to save.
class MemoryTextSizeStore implements ReaderTextSizeStore {
  MemoryTextSizeStore([this.size = ReaderTextSize.standard]);

  ReaderTextSize size;
  final saved = <ReaderTextSize>[];

  @override
  Future<ReaderTextSize> load() async => size;

  @override
  Future<void> save(ReaderTextSize size) async {
    saved.add(size);
    this.size = size;
  }
}

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

BlogModel _longArticle() => BlogModel(
  id: 'long',
  title: 'An unfinished page',
  content: [for (var i = 0; i < 40; i++) _paragraph].join('\n\n'),
  posterId: 'author',
  imageUrl: '',
  tags: const ['essay'],
  updatedAt: DateTime.utc(2025),
);

/// The size the article body is set at: the standard size, through the
/// scaler the text is laid out with.
double _bodySize(WidgetTester tester) => MediaQuery.textScalerOf(
  tester.element(find.byType(MarkdownBody)),
).scale(NoWaveTypeScale.articleBody);

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

void main() {
  setUp(() => GetIt.instance.reset());

  Future<_History> open(
    WidgetTester tester, {
    ReaderTextSizeController? textSize,
  }) async {
    final harness = Harness()..buildRouter(initialLocation: '/view/long');
    addTearDown(harness.dispose);
    final history = _History();
    GetIt.instance.registerSingleton<ReadingHistoryStore>(history);
    if (textSize != null) {
      GetIt.instance.registerSingleton<ReaderTextSizeController>(textSize);
    }
    final article = _longArticle();
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

  testWidgets('the text-size sheet resizes the article behind it', (
    tester,
  ) async {
    final store = MemoryTextSizeStore();
    final textSize = ReaderTextSizeController(store);
    addTearDown(textSize.dispose);
    final semantics = tester.ensureSemantics();
    await open(tester, textSize: textSize);

    expect(_bodySize(tester), NoWaveTypeScale.articleBody);

    await tester.tap(find.byKey(const ValueKey('reader-text-size')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderTextSizeSheet), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reader-text-size-largest')));
    await tester.pumpAndSettle();

    expect(textSize.value, ReaderTextSize.largest);
    expect(store.saved, [ReaderTextSize.largest]);
    expect(_bodySize(tester), closeTo(24, 0.001));
    // The sheet stays open, so the reader can try the next step against the
    // text itself.
    expect(find.byType(ReaderTextSizeSheet), findsOneWidget);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('reader-text-size-largest')),
      ),
      isSemantics(isButton: true, isSelected: true),
    );
    semantics.dispose();
  });

  testWidgets('a new size keeps the reader at the same share of the text', (
    tester,
  ) async {
    final textSize = ReaderTextSizeController(MemoryTextSizeStore());
    addTearDown(textSize.dispose);
    final history = await open(tester, textSize: textSize);

    await tester.drag(find.byType(BlogViewerPage), const Offset(0, -1500));
    await tester.pumpAndSettle();
    final before = history.saved.last;
    final pixelsBefore = _articleScroll(tester).pixels;
    expect(before, greaterThan(0));

    textSize.select(ReaderTextSize.largest);
    await tester.pumpAndSettle();

    // Larger text makes a longer page, so the same place sits further down.
    expect(_articleScroll(tester).pixels, greaterThan(pixelsBefore * 1.15));
    expect(history.saved.last, closeTo(before, 0.03));
  });

  testWidgets('the saved size is applied when the article opens', (
    tester,
  ) async {
    final textSize = ReaderTextSizeController(
      MemoryTextSizeStore(ReaderTextSize.small),
    );
    addTearDown(textSize.dispose);
    await textSize.load();
    await open(tester, textSize: textSize);

    expect(_bodySize(tester), closeTo(16, 0.001));
  });

  testWidgets('without a text-size store there is no button', (tester) async {
    await open(tester);

    expect(find.byKey(const ValueKey('reader-text-size')), findsNothing);
    expect(_bodySize(tester), NoWaveTypeScale.articleBody);
  });

  testWidgets('at a large system text size the steps stack, names whole', (
    tester,
  ) async {
    // The persona sweep's grace: a 412 dp phone at twice the text size,
    // where five names side by side were cut to their first letters and
    // the sheet ran past its bottom.
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final textSize = ReaderTextSizeController(MemoryTextSizeStore());
    addTearDown(textSize.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ReaderTextSizeSheet.show(context, textSize),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final names = ['Small', 'Default', 'Large', 'Larger', 'Largest'];
    for (final name in names) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isFalse, reason: name);
    }
    // One under another, in a single column.
    expect(
      tester.getTopLeft(find.text('Largest')).dx,
      tester.getTopLeft(find.text('Small')).dx,
    );

    // The whole line is the target, name included.
    await tester.ensureVisible(find.text('Largest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Largest'));
    await tester.pumpAndSettle();
    expect(textSize.value, ReaderTextSize.largest);
  });

  testWidgets('the size sits on top of the system text size', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: ReaderTextScale(
          factor: 1.5,
          child: Text('x', textDirection: TextDirection.ltr),
        ),
      ),
    );

    final scaler = MediaQuery.textScalerOf(tester.element(find.text('x')));
    expect(scaler.scale(10), 30);
  });
}
