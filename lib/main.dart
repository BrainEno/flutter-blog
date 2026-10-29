import 'dart:ui' show PlatformDispatcher;

import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/init_dependencies.dart';
import 'package:belog/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();

  await initDependencies();
  // Restore a persisted Supabase session before the first frame so the
  // router's auth redirect and tab visibility see the correct user state
  // instead of a logged-out flash.
  serviceLocator<AuthBloc>().add(AuthIsUserLoggedIn());
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => serviceLocator<ThemeBloc>()),
        BlocProvider(create: (_) => serviceLocator<AuthBloc>()),
        BlocProvider(create: (_) => serviceLocator<AppUserCubit>()),
      ],
      child: const BelogApp(),
    ),
  );
}

/// Routes framework and platform errors into the app logger.
///
/// No analytics/telemetry sink exists; this exists so failures are never
/// fully silent during development, and so async platform errors do not
/// crash-loop the app in release builds.
void _installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error(
      'Unhandled framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(
      'Unhandled platform error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
}

/// Root widget: theme plus routing.
///
/// Only the app-wide ThemeBloc, AuthBloc and AppUserCubit live above the
/// router. Every page-scoped bloc (feed, search, likes, upload, editor
/// state, profile edits) is created by its route in [createAppRouter] and
/// disposed together with that page, so state can no longer leak between
/// pages.
class BelogApp extends StatefulWidget {
  const BelogApp({super.key});

  @override
  State<BelogApp> createState() => _BelogAppState();
}

class _BelogAppState extends State<BelogApp> {
  late final GoRouter _router = createAppRouter(
    appUserCubit: serviceLocator<AppUserCubit>(),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, state) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          themeMode: state.themeMode,
          theme: AppTheme.lightThemeMode,
          darkTheme: AppTheme.darkThemeMode,
        );
      },
    );
  }
}
