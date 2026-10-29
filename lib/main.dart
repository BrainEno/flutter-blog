import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/global_snackbar.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/init_dependencies.dart';
import 'package:belog/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// How long the cold-start session restore may hold back the first frame.
/// Normally the restore resolves in well under a second; the bound only
/// guards against a hung network so the app still boots.
const _kSessionRestoreTimeout = Duration(seconds: 3);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();

  await initDependencies();
  // Restore the persisted no-wave session before the first frame so the
  // router's auth redirect and tab visibility see the correct user state
  // instead of a logged-out flash. The wait is bounded: a slow network
  // must not keep the app from starting, and the login page re-checks on
  // entry as a backstop.
  final authBloc = serviceLocator<AuthBloc>();
  authBloc.add(AuthIsUserLoggedIn());
  try {
    await authBloc.stream
        .firstWhere(
          (state) =>
              state is AuthSuccess ||
              state is AuthFailure ||
              state is AuthLogoutFailure,
        )
        .timeout(_kSessionRestoreTimeout);
  } on TimeoutException {
    AppLogger.debug('session restore timed out; continuing boot');
  }
  // Keep the app-wide identity cubit in sync with out-of-band session
  // events (a failed background token refresh drops the session).
  serviceLocator<AuthSessionSync>().start();
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
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          themeMode: state.themeMode,
          theme: AppTheme.lightThemeMode,
          darkTheme: AppTheme.darkThemeMode,
        );
      },
    );
  }
}
