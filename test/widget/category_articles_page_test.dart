import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_category.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:belog/features/blog/presentation/pages/category_articles_page.dart';
import 'package:belog/features/blog/presentation/widgets/blog_feed_skeleton.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetCategory extends Mock implements GetCategory {}

class _MockGetArticlesByCategory extends Mock
    implements GetArticlesByCategory {}

class _ArticlesParamsFake extends Fake implements CategoryArticlesParams {}

const _category = CategoryRef(slug: 'essay-1a2b', name: '随笔');

Blog _blog(String id, String title) => Blog(
  id: id,
  title: title,
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

Future<void> settle(WidgetTester tester, CategoryArticlesBloc bloc) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final state = bloc.state;
    if (state is CategoryArticlesSuccess ||
        state is CategoryArticlesNotFound ||
        state is CategoryArticlesFailure) {
      break;
    }
  }
  await tester.pump();
}

String screenText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .where((text) => text.isNotEmpty)
    .join(' | ');

String diagnostics(WidgetTester tester, CategoryArticlesBloc bloc) =>
    'state=${bloc.state.runtimeType} screen=${screenText(tester)}';

void main() {
  late _MockGetCategory getCategory;
  late _MockGetArticlesByCategory getArticlesByCategory;

  setUpAll(() => registerFallbackValue(_ArticlesParamsFake()));

  setUp(() {
    getCategory = _MockGetCategory();
    getArticlesByCategory = _MockGetArticlesByCategory();
    when(
      () => getCategory(_category.slug),
    ).thenAnswer((_) async => right(_category));
  });

  CategoryArticlesBloc newBloc() {
    final bloc = CategoryArticlesBloc(
      getCategory: getCategory,
      getArticlesByCategory: getArticlesByCategory,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    CategoryArticlesBloc bloc, {
    String? knownName,
    bool waitForResult = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CategoryArticlesPage(
            slug: _category.slug,
            knownName: knownName,
          ),
        ),
      ),
    );
    if (waitForResult) await settle(tester, bloc);
  }

  testWidgets('initial loading shows compact skeleton, then articles', (
    tester,
  ) async {
    final pending = Completer<Either<Failure, List<Blog>>>();
    when(() => getArticlesByCategory(any())).thenAnswer((_) => pending.future);
    final bloc = newBloc();
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

    try {
      await pumpPage(tester, bloc, waitForResult: false);
      await tester.pump();
      final skeleton = tester.widget<BlogFeedSkeleton>(
        find.byType(BlogFeedSkeleton),
      );
      expect(skeleton.showFeatured, isFalse);
      final l10n = lookupAppLocalizations(const Locale('zh'));
      expect(find.bySemanticsLabel(l10n.loadingArticles), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending.complete(right([_blog('a', 'Loaded article')]));
      await settle(tester, bloc);
      expect(bloc.state, isA<CategoryArticlesSuccess>());
      expect(find.byType(BlogFeedSkeleton), findsNothing);
      expect(find.text('Loaded article'), findsOneWidget);
    } finally {
      // Complete the held request inside the widget test's fake-async zone,
      // even if an assertion fails, before the bloc is closed by teardown.
      if (!pending.isCompleted) pending.complete(right(const <Blog>[]));
      await tester.pump();
    }
  });

  testWidgets('a category lists its articles under its own name', (
    tester,
  ) async {
    final bloc = newBloc();
    when(
      () => getArticlesByCategory(any()),
    ).thenAnswer((_) async => right([_blog('a', '随笔一则'), _blog('b', '第二篇')]));

    await pumpPage(tester, bloc);

    expect(
      bloc.state,
      isA<CategoryArticlesSuccess>(),
      reason: diagnostics(tester, bloc),
    );
    expect(find.text('随笔'), findsOneWidget);
    expect(
      find.text('随笔一则'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
    expect(find.text('第二篇'), findsOneWidget);
    verify(() => getArticlesByCategory(any())).called(1);
  });

  testWidgets('an empty category says so by name', (tester) async {
    final bloc = newBloc();
    when(
      () => getArticlesByCategory(any()),
    ).thenAnswer((_) async => right(const <Blog>[]));

    await pumpPage(tester, bloc);

    expect(
      find.text('「随笔」下还没有文章'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
  });

  testWidgets('a category that is gone is explicit, not an empty list', (
    tester,
  ) async {
    final bloc = newBloc();
    when(
      () => getCategory(_category.slug),
    ).thenAnswer((_) async => right(null));

    await pumpPage(tester, bloc);

    expect(
      find.textContaining('找不到这个分类'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
    verifyNever(() => getArticlesByCategory(any()));
  });

  testWidgets('a network failure offers a retry that reloads', (tester) async {
    final bloc = newBloc();
    var attempts = 0;
    when(() => getArticlesByCategory(any())).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) return left(Failure.networkOffline());
      return right([_blog('a', '随笔一则')]);
    });

    await pumpPage(tester, bloc);
    expect(
      find.textContaining('无法连接到网络'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );

    await tester.tap(find.text('重试'));
    await settle(tester, bloc);

    expect(
      find.text('随笔一则'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
    expect(attempts, 2);
  });

  testWidgets('a deep link without a known name waits for the lookup', (
    tester,
  ) async {
    final bloc = newBloc();
    when(
      () => getArticlesByCategory(any()),
    ).thenAnswer((_) async => right([_blog('a', '随笔一则')]));

    await pumpPage(tester, bloc);

    expect(find.text('随笔'), findsOneWidget, reason: diagnostics(tester, bloc));
    verify(() => getCategory(_category.slug)).called(1);
  });

  testWidgets('a name handed over by the tap is shown before the lookup', (
    tester,
  ) async {
    final bloc = newBloc();
    when(
      () => getArticlesByCategory(any()),
    ).thenAnswer((_) async => right([_blog('a', '随笔一则')]));

    await pumpPage(tester, bloc, knownName: '随笔');

    expect(find.text('随笔'), findsOneWidget);
  });
}
