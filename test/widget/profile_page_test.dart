import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/widgets/no_wave_action_row.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/user/domain/usecases/export_user_data.dart';
import 'package:belog/features/user/presentation/pages/profile_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockExporter extends Mock implements ExportUserData {}

class _ThemeStore implements ThemePreferenceStore {
  _ThemeStore(this.mode);
  ThemeMode mode;

  @override
  Future<ThemeMode> load() async => mode;

  @override
  Future<void> save(ThemeMode value) async => mode = value;
}

class _Harness {
  _Harness(this.user, {ThemeMode mode = ThemeMode.light}) {
    store = _ThemeStore(mode);
    theme = ThemeBloc(store);
    appUser = AppUserCubit()..updateUser(user);
    final repository = _MockAuthRepository();
    auth = AuthBloc(
      userSignUp: UserSignUp(repository),
      userLogin: UserLogin(repository),
      userSignOut: UserSignOut(repository),
      currentUser: CurrentUser(repository),
      appUserCubit: appUser,
      sessionGeneration: () => 0,
      hasActiveSession: () => false,
      isCurrentSessionUser: (_) => true,
    );
    router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, _) => const ProfilePage(),
          routes: [
            for (final path in ['edit', 'my-articles', 'history', 'about'])
              GoRoute(
                path: path,
                builder: (_, _) => Scaffold(body: Text('destination: $path')),
              ),
          ],
        ),
      ],
    );
  }

  final User user;
  late final _ThemeStore store;
  late final ThemeBloc theme;
  late final AppUserCubit appUser;
  late final AuthBloc auth;
  late final GoRouter router;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeBloc>.value(value: theme),
          BlocProvider<AppUserCubit>.value(value: appUser),
          BlocProvider<AuthBloc>.value(value: auth),
        ],
        child: BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, state) => MaterialApp.router(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightThemeMode,
            darkTheme: AppTheme.darkThemeMode,
            themeMode: state.themeMode,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    router.dispose();
    await auth.close();
    await appUser.close();
    await theme.close();
  }
}

User _user({String name = 'A reader'}) => User(
  id: 'viewer',
  email: 'viewer@example.invalid',
  name: name,
  avatarUrl: 'file:///not-a-portrait.png',
  website: 'https://example.invalid/a-long-profile-address',
  updatedAt: DateTime.utc(2025),
);

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('profile fits 320px and 2x text: $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final user = _user(name: 'A long author name with several words');
          final harness = _Harness(user, mode: mode);
          addTearDown(harness.dispose);
          final l10n = lookupAppLocalizations(locale);
          await harness.pump(tester, locale: locale, textScale: 2);

          expect(find.text(user.name), findsOneWidget);
          expect(find.text(user.website), findsOneWidget);
          expect(find.byType(NoWaveAvatar), findsOneWidget);
          expect(find.byIcon(Icons.person_outline), findsOneWidget);
          expect(
            find.bySemanticsLabel(l10n.avatarOf(user.name)),
            findsOneWidget,
          );
          expect(find.byType(NoWaveActionRow), findsNWidgets(6));
          for (final label in [
            l10n.menuEditProfile,
            l10n.menuMyArticles,
            l10n.menuReadingHistory,
            l10n.menuAbout,
            l10n.exportMyData,
            l10n.logout,
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.scrollUntilVisible(find.text(l10n.logout), 140);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('theme toggle changes and persists the selected mode', (
    tester,
  ) async {
    final harness = _Harness(_user());
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(harness.theme.state.themeMode, ThemeMode.dark);
    expect(harness.store.mode, ThemeMode.dark);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expect(harness.store.mode, ThemeMode.light);
  });

  testWidgets('profile actions navigate to the intended destinations', (
    tester,
  ) async {
    final harness = _Harness(_user());
    addTearDown(harness.dispose);
    await harness.pump(tester);
    for (final entry in <String, String>{
      'Edit profile': 'edit',
      'My articles': 'my-articles',
      'Reading history': 'history',
      'About': 'about',
    }.entries) {
      await tester.scrollUntilVisible(find.text(entry.key), 100);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.text('destination: ${entry.value}'), findsOneWidget);
      harness.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
    }
  });

  testWidgets('export remains guarded while in flight and reports failures', (
    tester,
  ) async {
    final user = _user();
    final harness = _Harness(user);
    final exporter = _MockExporter();
    final pending = Completer<Either<Failure, void>>();
    final l10n = lookupAppLocalizations(const Locale('en'));
    when(
      () => exporter.exportAndShare(
        user: user,
        shareTitle: l10n.exportShareTitle,
      ),
    ).thenAnswer((_) => pending.future);
    GetIt.instance.registerSingleton<ExportUserData>(exporter);
    addTearDown(() async {
      await harness.dispose();
      await GetIt.instance.reset();
    });
    await harness.pump(tester);
    await tester.scrollUntilVisible(find.text(l10n.exportMyData), 120);
    await tester.tap(find.text(l10n.exportMyData));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    verify(
      () => exporter.exportAndShare(
        user: user,
        shareTitle: l10n.exportShareTitle,
      ),
    ).called(1);

    pending.complete(left(Failure.networkOffline()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('No network connection — check your settings'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
