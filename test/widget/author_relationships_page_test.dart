import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/domain/repositories/author_relationship_repository.dart';
import 'package:belog/features/user/domain/usecases/get_author_relationships.dart';
import 'package:belog/features/user/presentation/bloc/author_relationships/author_relationships_cubit.dart';
import 'package:belog/features/user/presentation/pages/author_relationships_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

typedef Result = Either<Failure, List<AuthorRelationship>>;

class ScriptedRepository implements AuthorRelationshipRepository {
  final requests = <Completer<Result>>[];
  final arguments = <(String, AuthorRelationshipKind)>[];

  @override
  Future<Result> getRelationships({
    required String userId,
    required AuthorRelationshipKind kind,
  }) {
    arguments.add((userId, kind));
    final request = Completer<Result>();
    requests.add(request);
    return request.future;
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required AuthorRelationshipsCubit cubit,
  required AuthorRelationshipKind kind,
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  final router = GoRouter(
    initialLocation: '/search/author/owner/${kind.name}',
    routes: [
      GoRoute(
        path: '/search/author/:userId/${kind.name}',
        builder: (_, _) => BlocProvider<AuthorRelationshipsCubit>.value(
          value: cubit,
          child: AuthorRelationshipsPage(kind: kind),
        ),
      ),
      GoRoute(
        path: '/search/author/:userId',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('profile: ${state.pathParameters['userId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightThemeMode,
      darkTheme: AppTheme.darkThemeMode,
      themeMode: mode,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

void main() {
  testWidgets('loading, offline, retry and empty are distinct', (tester) async {
    final repository = ScriptedRepository();
    final cubit = AuthorRelationshipsCubit(
      getRelationships: GetAuthorRelationships(repository),
      userId: 'owner',
      kind: AuthorRelationshipKind.followers,
    );
    addTearDown(cubit.close);
    await _pumpPage(
      tester,
      cubit: cubit,
      kind: AuthorRelationshipKind.followers,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.requests[0].complete(left(Failure.networkOffline()));
    await tester.pumpAndSettle();
    expect(
      find.text('No network connection — check your settings'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No followers to show'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.requests[1].complete(right([]));
    await tester.pumpAndSettle();
    expect(find.text('No followers to show'), findsOneWidget);
    expect(find.byTooltip('Refresh list'), findsOneWidget);
    expect(repository.arguments, [
      ('owner', AuthorRelationshipKind.followers),
      ('owner', AuthorRelationshipKind.followers),
    ]);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'capped list remains legible and accessible at 2x: $locale $mode',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          addTearDown(semantics.dispose);
          final repository = ScriptedRepository();
          final cubit = AuthorRelationshipsCubit(
            getRelationships: GetAuthorRelationships(repository),
            userId: 'owner',
            kind: AuthorRelationshipKind.following,
          );
          addTearDown(cubit.close);
          await _pumpPage(
            tester,
            cubit: cubit,
            kind: AuthorRelationshipKind.following,
            locale: locale,
            mode: mode,
            textScale: 2,
          );
          repository.requests[0].complete(
            right(
              List.generate(
                100,
                (i) => AuthorRelationship(
                  userId: 'reader-$i',
                  displayName: i == 0 ? '' : 'Writer $i',
                  bio: i == 0 ? 'A longer biography for the first person.' : '',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = lookupAppLocalizations(locale);
          expect(find.text(l10n.followingTitle), findsOneWidget);
          expect(find.text(l10n.relationshipLimitNotice), findsOneWidget);
          expect(find.text(l10n.anonymousAuthor), findsOneWidget);
          expect(
            find.bySemanticsLabel(l10n.avatarOf(l10n.anonymousAuthor)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'a listed author opens in the same tab and back returns to the list',
    (tester) async {
      final repository = ScriptedRepository();
      final cubit = AuthorRelationshipsCubit(
        getRelationships: GetAuthorRelationships(repository),
        userId: 'owner',
        kind: AuthorRelationshipKind.followers,
      );
      addTearDown(cubit.close);
      await _pumpPage(
        tester,
        cubit: cubit,
        kind: AuthorRelationshipKind.followers,
      );
      repository.requests[0].complete(
        right([
          const AuthorRelationship(userId: 'reader', displayName: 'Reader'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Showing up to 100 people; there may be more.'),
        findsNothing,
      );
      await tester.tap(find.text('Reader'));
      await tester.pumpAndSettle();
      expect(find.text('profile: reader'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsOneWidget);
      expect(repository.requests, hasLength(1));
    },
  );
}
