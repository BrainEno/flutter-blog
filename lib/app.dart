import 'dart:ui' show PlatformDispatcher;

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/utils/article_deep_link.dart';
import 'package:belog/core/utils/global_snackbar.dart';
import 'package:belog/init_dependencies.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Root widget: theme, localization and routing.
///
/// Only the app-wide ThemeBloc, AuthBloc and AppUserCubit live above the
/// router. Every page-scoped bloc (feed, search, likes, upload, editor
/// state, profile edits) is created by its route in [createAppRouter] and
/// disposed together with that page, so state can no longer leak between
/// pages.
///
/// It is built by `NoWaveBootApp` once the injector is ready: this widget reads
/// `serviceLocator`, so it must never be constructed before boot succeeded.
///
/// Localization (issue #24): the system locale picks between the Chinese
/// and English ARB catalogs. `supportedLocales` lists Chinese first on
/// purpose - an unmatched device locale (say Japanese) falls back to
/// Chinese, the product's primary language, not to English.
class NoWaveApp extends StatefulWidget {
  const NoWaveApp({super.key});

  @override
  State<NoWaveApp> createState() => _NoWaveAppState();
}

class _NoWaveAppState extends State<NoWaveApp> {
  late final GoRouter _router = createAppRouter(
    appUserCubit: serviceLocator<AppUserCubit>(),
    // A cold start from `nowave://article/<slug>` arrives here as the whole
    // URL (issue #21); the reader is the first frame, not a 404.
    initialLocation: initialLocationForRoute(
      PlatformDispatcher.instance.defaultRouteName,
    ),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleBloc, LocaleState>(
      builder: (context, localeState) {
        return BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, state) {
            return MaterialApp.router(
              debugShowCheckedModeBanner: false,
              routerConfig: _router,
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              themeMode: state.themeMode,
              theme: AppTheme.lightThemeMode,
              darkTheme: AppTheme.darkThemeMode,
              // An explicit in-app choice pins the interface; `null` keeps
              // following the device through resolveAppLocale (issue #108).
              locale: localeState.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              localeListResolutionCallback: resolveAppLocale,
              supportedLocales: const [Locale('zh'), Locale('en')],
            );
          },
        );
      },
    );
  }
}
