import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/user/data/models/author_profile_model.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:belog/features/user/domain/usecases/browse_authors.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:belog/features/user/presentation/pages/author_page.dart';
import 'package:belog/features/user/presentation/pages/author_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness;

class MockAuthorSearch extends Mock implements AuthorSearchRepository {}

void main() {
  setUp(() => GetIt.instance.reset());

  testWidgets('search entry, author route and back stay in the search tab', (
    tester,
  ) async {
    const readerId = 'reader/with?reserved%';
    final search = MockAuthorSearch();
    final harness = Harness()..buildRouter(initialLocation: '/search');
    addTearDown(harness.dispose);
    GetIt.instance.registerFactory(() => SearchAuthors(search));
    GetIt.instance.registerFactory(() => BrowseAuthors(search));
    when(() => search.directory(offset: 0)).thenAnswer((_) async => right([]));
    when(() => search.search('读者', offset: 0)).thenAnswer(
      (_) async => right([
        const AuthorSearchResult(userId: readerId, displayName: '读者乙'),
      ]),
    );
    when(() => harness.authorRemote.getAuthorProfile(readerId)).thenAnswer(
      (_) async => AuthorProfileModel(
        userId: readerId,
        displayName: '读者乙的主页',
        updatedAt: DateTime.utc(2025),
      ),
    );
    when(
      () => harness.remote.getBlogsByPosterId(readerId),
    ).thenAnswer((_) async => <BlogModel>[]);
    await harness.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(SearchBlogPage), findsOneWidget);
    await tester.tap(find.text('搜索作者'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthorSearchPage), findsOneWidget);
    await tester.enterText(find.byType(TextField), '读者');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('读者乙'), findsOneWidget);
    await tester.tap(find.text('读者乙'));
    await tester.pumpAndSettle();
    expect(find.text('读者乙的主页'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    verify(() => harness.authorRemote.getAuthorProfile(readerId)).called(1);

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthorPage), findsOneWidget);
    final back = MaterialLocalizations.of(
      tester.element(find.byType(AuthorPage)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(back));
    await tester.pumpAndSettle();
    expect(find.byType(AuthorSearchPage), findsOneWidget);
    expect(find.text('读者乙'), findsOneWidget);
    expect(find.text('读者'), findsOneWidget);
    verify(() => search.search('读者', offset: 0)).called(1);
    await tester.tap(find.byTooltip(back));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBlogPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
