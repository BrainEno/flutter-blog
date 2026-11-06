import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/presentation/blocs/categories/categories_cubit.dart';
import 'package:belog/features/blog/presentation/pages/categories_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetCategories extends Mock implements GetCategories {}

class _NoParamsFake extends Fake implements NoParams {}

CategoryRef _category(String slug, String name, {String description = ''}) =>
    CategoryRef(slug: slug, name: name, description: description);

/// Pumps until the cubit leaves its loading state.
///
/// `pumpAndSettle` cannot be used while the loading spinner is on screen: it
/// would keep scheduling frames and time the test out.
Future<void> settle(WidgetTester tester, CategoriesCubit cubit) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final state = cubit.state;
    if (state is CategoriesSuccess || state is CategoriesFailure) break;
  }
  await tester.pump();
}

String screenText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .where((text) => text.isNotEmpty)
    .join(' | ');

String diagnostics(WidgetTester tester, CategoriesCubit cubit) =>
    'state=${cubit.state.runtimeType} screen=${screenText(tester)}';

void main() {
  late _MockGetCategories getCategories;

  setUpAll(() => registerFallbackValue(_NoParamsFake()));

  setUp(() {
    getCategories = _MockGetCategories();
  });

  /// Built inside the test body: a cubit created in `setUp` lives in the outer
  /// zone, and its events would never be delivered under the test's clock.
  CategoriesCubit newCubit() {
    final cubit = CategoriesCubit(getCategories: getCategories);
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> pumpPage(WidgetTester tester, CategoriesCubit cubit) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/categories',
      routes: [
        GoRoute(
          path: '/categories',
          builder: (context, state) =>
              BlocProvider.value(value: cubit, child: const CategoriesPage()),
        ),
        GoRoute(
          path: '/category/:slug',
          builder: (context, state) =>
              Text('detail:${state.pathParameters['slug']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await settle(tester, cubit);
  }

  testWidgets('the catalog lists the categories the server names', (
    tester,
  ) async {
    final cubit = newCubit();
    when(() => getCategories(any())).thenAnswer(
      (_) async => right([
        _category('essay-1a2b', '随笔', description: '短小的日常记录'),
        _category('poetry-9z', '诗歌'),
      ]),
    );

    await pumpPage(tester, cubit);

    expect(
      cubit.state,
      isA<CategoriesSuccess>(),
      reason: diagnostics(tester, cubit),
    );
    expect(find.text('分类'), findsWidgets);
    expect(find.text('随笔'), findsOneWidget, reason: diagnostics(tester, cubit));
    expect(find.text('短小的日常记录'), findsOneWidget);
    expect(find.text('诗歌'), findsOneWidget);
    expect(find.textContaining('分类由编辑维护'), findsOneWidget);
  });

  testWidgets('an empty catalog says so instead of looking broken', (
    tester,
  ) async {
    final cubit = newCubit();
    when(
      () => getCategories(any()),
    ).thenAnswer((_) async => right(const <CategoryRef>[]));

    await pumpPage(tester, cubit);

    expect(
      find.text('服务器未返回分类。'),
      findsOneWidget,
      reason: diagnostics(tester, cubit),
    );
  });

  testWidgets('a full page warns that the catalog may continue', (
    tester,
  ) async {
    final cubit = newCubit();
    when(() => getCategories(any())).thenAnswer(
      (_) async =>
          right([for (var i = 0; i < 100; i++) _category('cat-$i', '分类 $i')]),
    );

    await pumpPage(tester, cubit);
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pump();

    expect(
      find.text('只显示前 100 个分类，可能还有更多。'),
      findsOneWidget,
      reason: diagnostics(tester, cubit),
    );
  });

  testWidgets('a short page does not claim there are more', (tester) async {
    final cubit = newCubit();
    when(
      () => getCategories(any()),
    ).thenAnswer((_) async => right([_category('essay-1a2b', '随笔')]));

    await pumpPage(tester, cubit);

    expect(find.textContaining('可能还有更多'), findsNothing);
  });

  testWidgets('a failure offers a retry that reloads', (tester) async {
    final cubit = newCubit();
    var attempts = 0;
    when(() => getCategories(any())).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) {
        return left(
          const Failure(
            '此服务器暂不提供分类',
            kind: FailureKind.server,
            code: 'categories.unavailable',
          ),
        );
      }
      return right([_category('essay-1a2b', '随笔')]);
    });

    await pumpPage(tester, cubit);
    expect(
      find.textContaining('此服务器暂不提供分类'),
      findsOneWidget,
      reason: diagnostics(tester, cubit),
    );

    await tester.tap(find.text('重试'));
    await settle(tester, cubit);

    expect(find.text('随笔'), findsOneWidget, reason: diagnostics(tester, cubit));
    expect(attempts, 2);
  });

  testWidgets('tapping a category opens its articles', (tester) async {
    final cubit = newCubit();
    when(
      () => getCategories(any()),
    ).thenAnswer((_) async => right([_category('essay-1a2b', '随笔')]));

    await pumpPage(tester, cubit);
    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();

    expect(find.text('detail:essay-1a2b'), findsOneWidget);
  });
}
