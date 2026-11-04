import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import '../support/locale_test_support.dart';

class _GetFeed implements GetAllBlogs {
  _GetFeed(this.handler);

  final Future<Either<Failure, BlogFeedPage>> Function(GetAllBlogsParams)
  handler;

  @override
  Future<Either<Failure, BlogFeedPage>> call(GetAllBlogsParams params) =>
      handler(params);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Blog _article(String id) => Blog(
  id: id,
  posterId: 'author',
  title: 'title $id',
  content: 'body',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime(2026, 10, 30),
);

void main() {
  testWidgets('a content-language switch starts a new feed session', (
    tester,
  ) async {
    final content = ContentLocale();
    final localeBloc = LocaleBloc(
      SystemLocalePreferenceStore(),
      contentLocale: content,
      deviceLocale: () => const Locale('zh'),
    );
    addTearDown(localeBloc.close);
    final user = AppUserCubit();
    addTearDown(user.close);

    var calls = 0;
    final bloc = BlogBloc(
      getAllBlogs: _GetFeed((params) async {
        calls++;
        return right(
          BlogFeedPage(blogs: [_article('a$calls')], source: BlogFeedSource.network),
        );
      }),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BlogBloc>.value(value: bloc),
          BlocProvider<AppUserCubit>.value(value: user),
          BlocProvider<LocaleBloc>.value(value: localeBloc),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('zh'), Locale('en')],
          home: BlogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    // Selecting English changes the content language, so the feed must not
    // keep rendering the Chinese page it already has.
    localeBloc.add(SetAppLanguage(AppLanguage.en));
    await tester.pumpAndSettle();

    expect(content.tag, 'en');
    expect(calls, 2);

    // An interface change that resolves to the same content language keeps
    // the session and does not refetch.
    localeBloc.add(SetAppLanguage(AppLanguage.zh));
    await tester.pumpAndSettle();
    expect(calls, 3);
    localeBloc.add(SetAppLanguage(AppLanguage.zh));
    await tester.pumpAndSettle();
    expect(calls, 3);
  });

  testWidgets('a slow page from the old language is not appended', (
    tester,
  ) async {
    final content = ContentLocale();
    final localeBloc = LocaleBloc(
      SystemLocalePreferenceStore(),
      contentLocale: content,
      deviceLocale: () => const Locale('zh'),
    );
    addTearDown(localeBloc.close);
    final user = AppUserCubit();
    addTearDown(user.close);

    final slow = Completer<Either<Failure, BlogFeedPage>>();
    var calls = 0;
    final bloc = BlogBloc(
      getAllBlogs: _GetFeed((params) {
        calls++;
        if (calls == 1) return slow.future;
        return Future.value(
          right(
            BlogFeedPage(
              blogs: [_article('fresh')],
              source: BlogFeedSource.network,
            ),
          ),
        );
      }),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BlogBloc>.value(value: bloc),
          BlocProvider<AppUserCubit>.value(value: user),
          BlocProvider<LocaleBloc>.value(value: localeBloc),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('zh'), Locale('en')],
          home: BlogPage(),
        ),
      ),
    );
    await tester.pump();

    localeBloc.add(SetAppLanguage(AppLanguage.en));
    await tester.pumpAndSettle();

    // The Chinese request finishes late; its page must be dropped rather than
    // mixed into the English list.
    slow.complete(
      right(
        BlogFeedPage(blogs: [_article('stale')], source: BlogFeedSource.network),
      ),
    );
    await tester.pumpAndSettle();

    final state = bloc.state;
    expect(state, isA<BlogLoaded>());
    expect((state as BlogLoaded).blogs.map((blog) => blog.id), ['fresh']);
  });
}
