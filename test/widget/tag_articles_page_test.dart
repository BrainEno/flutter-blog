import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/tag_paging.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:belog/features/blog/presentation/pages/tag_articles_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockResolveTag extends Mock implements ResolveTag {}

class _MockGetArticlesByTag extends Mock implements GetArticlesByTag {}

class _ResolveParamsFake extends Fake implements ResolveTagParams {}

class _ArticlesParamsFake extends Fake implements TagArticlesParams {}

const _tag = TagRef(name: '诗歌', slug: 'poetry-1a2b');

Blog _blog(String id, String title) => Blog(
  id: id,
  title: title,
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const ['诗歌'],
  updatedAt: DateTime.utc(2026),
);

void main() {
  late _MockResolveTag resolveTag;
  late _MockGetArticlesByTag getArticlesByTag;
  late TagArticlesBloc bloc;

  setUpAll(() {
    registerFallbackValue(_ResolveParamsFake());
    registerFallbackValue(_ArticlesParamsFake());
  });

  setUp(() {
    resolveTag = _MockResolveTag();
    getArticlesByTag = _MockGetArticlesByTag();
    when(() => resolveTag(any())).thenAnswer((_) async => right(_tag));
    bloc = TagArticlesBloc(
      resolveTag: resolveTag,
      getArticlesByTag: getArticlesByTag,
    );
    addTearDown(bloc.close);
  });

  Future<void> pumpPage(WidgetTester tester, {String tag = '诗歌'}) async {
    // The list is long enough that the footer would ask for a second page;
    // keep the window tall so the assertions stay about states, not layout.
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
          home: TagArticlesPage(tag: tag),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a tag lists its articles under its own name', (tester) async {
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer((_) async => right([_blog('a', '夜航手记'), _blog('b', '第二篇')]));

    await pumpPage(tester);

    expect(find.text('#诗歌'), findsOneWidget);
    expect(find.text('夜航手记'), findsOneWidget);
    expect(find.text('第二篇'), findsOneWidget);
    verify(() => getArticlesByTag(any())).called(1);
  });

  testWidgets('an existing tag with nothing filed under it says so', (
    tester,
  ) async {
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer((_) async => right(const <Blog>[]));

    await pumpPage(tester);

    expect(find.text('「诗歌」下还没有文章'), findsOneWidget);
  });

  testWidgets('an unknown tag is explicit instead of showing everything', (
    tester,
  ) async {
    when(() => resolveTag(any())).thenAnswer((_) async => right(null));

    await pumpPage(tester, tag: '不存在的');

    expect(find.text('找不到标签「不存在的」'), findsOneWidget);
    verifyNever(() => getArticlesByTag(any()));
  });

  testWidgets('a failure offers a retry that reloads', (tester) async {
    var attempts = 0;
    when(() => getArticlesByTag(any())).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) return left(Failure.networkOffline());
      return right([_blog('a', '夜航手记')]);
    });

    await pumpPage(tester);
    expect(find.textContaining('无法连接到网络'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('夜航手记'), findsOneWidget);
    expect(attempts, 2);
  });
}
