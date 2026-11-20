import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/reading_stats.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/user/presentation/pages/reading_history_page.dart';
import 'package:belog/features/user/presentation/widgets/reading_stats_card.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 19, 15);

ReadingHistoryEntry _entry(String id, int daysAgo) => ReadingHistoryEntry(
  blogId: id,
  title: 'article $id',
  posterName: '',
  imageUrl: '',
  readAt: DateTime(_now.year, _now.month, _now.day - daysAgo, 9),
);

class _Store implements ReadingHistoryStore {
  final List<ReadingHistoryEntry> entries;
  final List<String> removed = [];

  _Store(this.entries);

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async => List.of(entries);

  @override
  Future<void> record({required String userId, required Blog blog}) async {}

  @override
  Future<void> remove({required String userId, required String blogId}) async {
    removed.add(blogId);
  }

  @override
  Future<void> clear({required String userId}) async {}
}

Future<void> _pumpCard(
  WidgetTester tester,
  ReadingStats stats, {
  Locale locale = const Locale('zh'),
  double textScale = 1,
  Size size = const Size(800, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: ReadingStatsCard(stats: stats)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _figure(WidgetTester tester, String key) {
  final column = find.byKey(ValueKey(key));
  final texts = tester
      .widgetList<Text>(
        find.descendant(of: column, matching: find.byType(Text)),
      )
      .map((text) => text.data)
      .toList();
  return texts.first!;
}

void main() {
  final stats = ReadingStats.from([
    _entry('a', 0),
    _entry('b', 0),
    _entry('c', 1),
    _entry('d', 2),
    _entry('e', 9),
    _entry('f', 10),
    _entry('g', 11),
    _entry('h', 12),
  ], now: _now);

  testWidgets('shows the window, streak and total figures', (tester) async {
    await _pumpCard(tester, stats);
    final zh = lookupAppLocalizations(const Locale('zh'));

    expect(find.text(zh.readingStatsTitle), findsOneWidget);
    expect(_figure(tester, 'reading-stats-window'), '4');
    expect(_figure(tester, 'reading-stats-streak'), '3');
    expect(_figure(tester, 'reading-stats-total'), '8');
    expect(find.text(zh.readingStatsWindowLabel), findsOneWidget);
    expect(find.text(zh.readingStatsLongest(4)), findsOneWidget);
    expect(find.text(zh.readingStatsFootnote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the activity strip is announced as one sentence', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpCard(tester, stats, locale: const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    final prefix = en.readingStatsChart('');
    final chart = find.bySemanticsLabel(RegExp('^${RegExp.escape(prefix)}'));
    expect(chart, findsOneWidget);
    final days = tester.getSemantics(chart).label.substring(prefix.length);
    // Seven days, oldest first; today carries the two reads.
    expect(days, endsWith('2 articles'));
    expect(days, contains('1 article'));
    expect(days, contains('no reading'));
    expect(days.split(', '), hasLength(ReadingStats.windowDays));
    handle.dispose();
  });

  testWidgets('figures merge with their captions for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpCard(tester, stats, locale: const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    expect(
      find.bySemanticsLabel('3\n${en.readingStatsStreakLabel}'),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('${locale.languageCode}: survives 2x text at 320dp', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        stats,
        locale: locale,
        textScale: 2,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ReadingStatsCard), findsOneWidget);
    });
  }

  group('on the reading history page', () {
    late AppUserCubit cubit;

    setUp(() {
      cubit = AppUserCubit()
        ..updateUser(
          User(
            id: 'u1',
            email: 'reader@example.invalid',
            name: 'reader',
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );
    });
    tearDown(() => cubit.close());

    Future<void> pumpPage(
      WidgetTester tester,
      ReadingHistoryStore store,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        BlocProvider<AppUserCubit>.value(
          value: cubit,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReadingHistoryPage(store: store, clock: () => _now),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sits above the list and counts what is loaded', (
      tester,
    ) async {
      await pumpPage(tester, _Store([_entry('a', 0), _entry('b', 1)]));

      expect(find.byType(ReadingStatsCard), findsOneWidget);
      expect(_figure(tester, 'reading-stats-total'), '2');
      expect(_figure(tester, 'reading-stats-streak'), '2');
      final cardTop = tester.getTopLeft(find.byType(ReadingStatsCard)).dy;
      final rowTop = tester.getTopLeft(find.text('article a')).dy;
      expect(cardTop, lessThan(rowTop));
    });

    testWidgets('follows a removal without reloading', (tester) async {
      final store = _Store([_entry('a', 0), _entry('b', 1)]);
      await pumpPage(tester, store);

      await tester.tap(find.byTooltip('删除这条记录').first);
      await tester.pumpAndSettle();

      expect(store.removed, ['a']);
      expect(_figure(tester, 'reading-stats-total'), '1');
      // Today's read is gone; yesterday still keeps the streak alive.
      expect(_figure(tester, 'reading-stats-streak'), '1');
    });

    testWidgets('is absent when the history is empty', (tester) async {
      await pumpPage(tester, _Store([]));

      expect(find.byType(ReadingStatsCard), findsNothing);
      expect(find.text('还没有阅读记录'), findsOneWidget);
    });
  });
}
