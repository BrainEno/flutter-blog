import 'dart:async';

import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/user/presentation/pages/reading_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore implements ReadingHistoryStore {
  final List<ReadingHistoryEntry> entries;
  final List<String> removed = [];
  final List<String> cleared = [];
  int recordCalls = 0;

  _FakeStore(this.entries);

  @override
  Future<void> record({required String userId, required Blog blog}) async {
    recordCalls++;
  }

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) async => entries;

  @override
  Future<void> remove({required String userId, required String blogId}) async {
    removed.add(blogId);
  }

  @override
  Future<void> clear({required String userId}) async {
    cleared.add(userId);
  }
}

class _ControlledStore extends _FakeStore {
  _ControlledStore() : super([]);

  final Map<String, List<Completer<List<ReadingHistoryEntry>>>> requests = {};

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 200,
  }) {
    final pending = Completer<List<ReadingHistoryEntry>>();
    requests.putIfAbsent(userId, () => []).add(pending);
    return pending.future;
  }
}

ReadingHistoryEntry _entry(String id, String title) => ReadingHistoryEntry(
  blogId: id,
  title: title,
  posterName: '',
  imageUrl: '',
  readAt: DateTime.utc(2026, 10, 1),
);

void main() {
  late AppUserCubit cubit;
  final user = User(
    id: 'u1',
    email: 'author@example.invalid',
    name: '作者',
    updatedAt: DateTime.utc(2026, 10, 1),
  );

  setUp(() => cubit = AppUserCubit()..updateUser(user));
  tearDown(() => cubit.close());

  Future<void> pumpPage(
    WidgetTester tester,
    ReadingHistoryStore store, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      BlocProvider<AppUserCubit>.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReadingHistoryPage(store: store),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('renders the recorded reads newest-first', (tester) async {
    final store = _FakeStore([
      ReadingHistoryEntry(
        blogId: 'b',
        title: '较新的文章',
        posterName: '作者',
        imageUrl: '',
        readAt: DateTime(2026, 10, 30),
      ),
      ReadingHistoryEntry(
        blogId: 'a',
        title: '较早的文章',
        posterName: '',
        imageUrl: '',
        readAt: DateTime(2026, 10, 29),
      ),
    ]);
    await pumpPage(tester, store);

    expect(find.text('较新的文章'), findsOneWidget);
    expect(find.text('较早的文章'), findsOneWidget);
    // No poster name: the date renders alone, never as "null · ...".
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('switching accounts hides the old list and ignores late loads', (
    tester,
  ) async {
    final store = _ControlledStore();
    await pumpPage(tester, store, settle: false);
    expect(store.requests['u1'], hasLength(1));

    cubit.updateUser(
      User(
        id: 'u2',
        email: 'b@example.invalid',
        name: 'B',
        updatedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(store.requests['u2'], hasLength(1));
    store.requests['u2']!.single.complete([_entry('b', 'B private history')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('B private history'), findsOneWidget);

    store.requests['u1']!.single.complete([_entry('a', 'A private history')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('A private history'), findsNothing);
    expect(find.text('B private history'), findsOneWidget);
  });

  testWidgets('a visible old list is hidden immediately after account switch', (
    tester,
  ) async {
    final store = _ControlledStore();
    await pumpPage(tester, store, settle: false);
    store.requests['u1']!.single.complete([_entry('a', 'A private history')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('A private history'), findsOneWidget);

    cubit.updateUser(
      User(
        id: 'u2',
        email: 'b@example.invalid',
        name: 'B',
        updatedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('A private history'), findsNothing);
    expect(store.requests['u2'], hasLength(1));
    store.requests['u2']!.single.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('account switch cancels the old account clear confirmation', (
    tester,
  ) async {
    final store = _ControlledStore();
    await pumpPage(tester, store, settle: false);
    store.requests['u1']!.single.complete([_entry('a', 'A private history')]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空阅读历史'));
    await tester.pumpAndSettle();

    cubit.updateUser(
      User(
        id: 'u2',
        email: 'b@example.invalid',
        name: 'B',
        updatedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    await tester.pump();
    store.requests['u2']!.single.complete([]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(store.cleared, isEmpty);
  });

  testWidgets('an empty history explains itself', (tester) async {
    await pumpPage(tester, _FakeStore([]));

    expect(find.text('还没有阅读记录'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('the trailing button removes one entry', (tester) async {
    final store = _FakeStore([
      ReadingHistoryEntry(
        blogId: 'a',
        title: '标题',
        posterName: '',
        imageUrl: '',
        readAt: DateTime(2026, 10, 30),
      ),
    ]);
    await pumpPage(tester, store);

    await tester.tap(find.byTooltip('删除这条记录'));
    await tester.pumpAndSettle();

    expect(store.removed, ['a']);
  });

  testWidgets('clear-all asks for confirmation first', (tester) async {
    final store = _FakeStore([
      ReadingHistoryEntry(
        blogId: 'a',
        title: '标题',
        posterName: '',
        imageUrl: '',
        readAt: DateTime(2026, 10, 30),
      ),
    ]);
    await pumpPage(tester, store);

    await tester.tap(find.byTooltip('清空阅读历史'));
    await tester.pumpAndSettle();
    expect(store.cleared, isEmpty);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(store.cleared, ['u1']);
    expect(find.text('标题'), findsNothing);
  });

  testWidgets('swiping an entry away removes it', (tester) async {
    final store = _FakeStore([
      ReadingHistoryEntry(
        blogId: 'a',
        title: '标题',
        posterName: '',
        imageUrl: '',
        readAt: DateTime(2026, 10, 30),
      ),
    ]);
    await pumpPage(tester, store);

    await tester.drag(find.text('标题'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(store.removed, ['a']);
  });
}
