import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:belog/features/blog/presentation/pages/tag_articles_page.dart';
import 'package:belog/features/blog/presentation/widgets/blog_feed_skeleton.dart';
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

/// Pumps until the bloc leaves its loading states.
///
/// The request may still be pending even when no frames are scheduled, so
/// wait for a settled bloc state rather than only for animations to finish.
Future<void> settle(WidgetTester tester, TagArticlesBloc bloc) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final state = bloc.state;
    if (state is TagArticlesSuccess ||
        state is TagArticlesUnknown ||
        state is TagArticlesFailure) {
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

/// What is actually on screen, for failure messages.
String diagnostics(WidgetTester tester, TagArticlesBloc bloc) =>
    'state=${bloc.state.runtimeType} screen=${screenText(tester)}';

void main() {
  late _MockResolveTag resolveTag;
  late _MockGetArticlesByTag getArticlesByTag;

  setUpAll(() {
    registerFallbackValue(_ResolveParamsFake());
    registerFallbackValue(_ArticlesParamsFake());
  });

  setUp(() {
    resolveTag = _MockResolveTag();
    getArticlesByTag = _MockGetArticlesByTag();
    when(() => resolveTag(any())).thenAnswer((_) async => right(_tag));
  });

  /// Built inside the test body on purpose: a bloc created in `setUp` lives
  /// in the outer zone, and its events would never be delivered while the
  /// widget test's fake clock is running.
  TagArticlesBloc newBloc() {
    final bloc = TagArticlesBloc(
      resolveTag: resolveTag,
      getArticlesByTag: getArticlesByTag,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    TagArticlesBloc bloc, {
    String tag = '诗歌',
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
          home: TagArticlesPage(tag: tag),
        ),
      ),
    );
    if (waitForResult) await settle(tester, bloc);
  }

  testWidgets('initial loading shows compact skeleton, then articles', (
    tester,
  ) async {
    final pending = Completer<Either<Failure, List<Blog>>>();
    when(() => getArticlesByTag(any())).thenAnswer((_) => pending.future);
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
      expect(bloc.state, isA<TagArticlesSuccess>());
      expect(find.byType(BlogFeedSkeleton), findsNothing);
      expect(find.text('Loaded article'), findsOneWidget);
    } finally {
      // Complete the held request inside the widget test's fake-async zone,
      // even if an assertion fails, before the bloc is closed by teardown.
      if (!pending.isCompleted) pending.complete(right(const <Blog>[]));
      await tester.pump();
    }
  });

  testWidgets('a tag lists its articles under its own name', (tester) async {
    final bloc = newBloc();
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer((_) async => right([_blog('a', '夜航手记'), _blog('b', '第二篇')]));

    await pumpPage(tester, bloc);

    expect(
      bloc.state,
      isA<TagArticlesSuccess>(),
      reason: diagnostics(tester, bloc),
    );
    expect(find.text('#诗歌'), findsOneWidget);
    expect(
      find.text('夜航手记'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
    expect(find.text('第二篇'), findsOneWidget, reason: diagnostics(tester, bloc));
    verify(() => getArticlesByTag(any())).called(1);
  });

  testWidgets('an existing tag with nothing filed under it says so', (
    tester,
  ) async {
    final bloc = newBloc();
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer((_) async => right(const <Blog>[]));

    await pumpPage(tester, bloc);

    expect(
      find.text('「诗歌」下还没有文章'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
  });

  testWidgets('an unknown tag is explicit instead of showing everything', (
    tester,
  ) async {
    final bloc = newBloc();
    when(() => resolveTag(any())).thenAnswer((_) async => right(null));

    await pumpPage(tester, bloc, tag: '不存在的');

    expect(
      find.text('找不到标签「不存在的」'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
    verifyNever(() => getArticlesByTag(any()));
  });

  testWidgets('a failure offers a retry that reloads', (tester) async {
    final bloc = newBloc();
    var attempts = 0;
    when(() => getArticlesByTag(any())).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) return left(Failure.networkOffline());
      return right([_blog('a', '夜航手记')]);
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
      find.text('夜航手记'),
      findsOneWidget,
      reason: diagnostics(tester, bloc),
    );
    expect(attempts, 2);
  });
}
