import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/viewer/reading_marks.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_item.dart';
import 'package:belog/features/blog/presentation/widgets/reading_mark.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'no_wave_design_test.dart' show article, testApp;

/// One reader's history in memory.
class _History implements ReadingHistoryStore {
  _History(this.progress);

  final Map<String, double?> progress;

  @override
  Future<void> record({required String userId, required Blog blog}) async {
    progress.putIfAbsent(blog.id, () => null);
  }

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async => [
    for (final MapEntry(:key, :value) in progress.entries)
      ReadingHistoryEntry(
        blogId: key,
        title: key,
        posterName: '',
        imageUrl: '',
        readAt: DateTime.utc(2025),
        progress: value,
      ),
  ];

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async {
    this.progress[blogId] = progress;
  }

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) async => progress[blogId];

  @override
  Future<void> remove({required String userId, required String blogId}) async {
    progress.remove(blogId);
  }

  @override
  Future<void> clear({required String userId}) async => progress.clear();
}

void main() {
  late AppUserCubit users;
  late ReadingMarks marks;

  /// A signed-in reader who got 42% into "an-article"; the marks registered
  /// the way the app registers them.
  Future<void> signIn(WidgetTester tester) async {
    users = AppUserCubit()
      ..updateUser(
        User(
          id: 'ann',
          email: 'ann@example.com',
          name: 'Ann',
          updatedAt: DateTime.utc(2025),
        ),
      );
    marks = ReadingMarks(_History({'an-article': 0.42}), users: users);
    GetIt.instance.registerSingleton<ReadingMarks>(marks);
    addTearDown(() async {
      await GetIt.instance.reset();
      marks.dispose();
      await users.close();
    });
    await tester.pump();
  }

  testWidgets('a row says how far the reader got, and follows them', (
    tester,
  ) async {
    await signIn(tester);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: ListView(
            children: [
              BlogCard(blog: article(), onTap: () {}),
              BlogCard(
                blog: article(id: 'unread'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reading-mark-an-article')),
      findsOneWidget,
    );
    expect(find.text('42% read'), findsOneWidget);
    // An article never opened says nothing.
    expect(find.byKey(const ValueKey('reading-mark-unread')), findsNothing);

    // Reading on (the reader saves through the same history) updates the
    // list underneath without a reload.
    await marks.saveProgress(
      userId: 'ann',
      blogId: 'an-article',
      progress: 0.97,
    );
    await tester.pump();
    expect(find.text('42% read'), findsNothing);
    expect(find.text('Finished'), findsOneWidget);

    // Signing out takes the marks with the account.
    users.updateUser(null);
    await tester.pump();
    expect(find.text('Finished'), findsNothing);
  });

  testWidgets('a grid tile keeps the mark on its date line', (tester) async {
    await signIn(tester);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Builder(
            builder: (context) => GridView(
              gridDelegate: blogGridDelegate(context),
              children: [BlogGridItem(blog: article(), onTap: () {})],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(' · 42% read'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without registered marks a row has no mark', (tester) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: BlogCard(blog: article(), onTap: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reading-mark-an-article')), findsNothing);
  });

  test('the words for each stage, in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final zh = lookupAppLocalizations(const Locale('zh'));
    const english = Locale('en');
    expect(readingMarkLabel(en, english, null), isNull);
    expect(readingMarkLabel(en, english, 0.01), isNull);
    expect(readingMarkLabel(en, english, 0.42), '42% read');
    expect(readingMarkLabel(en, english, 0.99), 'Finished');
    expect(readingMarkLabel(zh, const Locale('zh'), 0.99), zh.historyFinished);
  });
}
