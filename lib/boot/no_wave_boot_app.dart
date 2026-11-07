import 'dart:async';

import 'package:belog/app.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/boot/boot_sequence.dart';
import 'package:belog/boot/no_wave_splash_screen.dart';
import 'package:belog/boot/startup_failure_app.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/init_dependencies.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Runs everything the app needs before its first route; throws when the
/// injector itself cannot be built.
typedef BootRunner = Future<void> Function();

/// What `main()` starts: the curtain first, the app as soon as it is usable.
///
/// The ordering matters. `runApp` happens immediately, with no dependency work
/// in front of it, so the operating system's static launch image is replaced by
/// a live frame as fast as the engine can draw one. Boot then runs *inside* the
/// app, in parallel with the curtain animation, and the real tree is built
/// behind the closing columns so lifting them reveals content rather than a
/// black rectangle.
///
/// A boot failure does not get the theatrical treatment: it renders
/// [StartupFailureApp] as soon as it is known, because "your configuration is
/// broken" is the one message that must not wait three seconds.
class NoWaveBootApp extends StatefulWidget {
  const NoWaveBootApp({super.key, this.boot = runBootSequence, this.appBuilder});

  /// What has to succeed before the app can be built. Injectable so a test can
  /// drive the boot screen without the service locator.
  final BootRunner boot;

  /// Builds the app behind the curtain. Defaults to the real root; a test
  /// supplies a stand-in for the same reason.
  final Widget Function()? appBuilder;

  @override
  State<NoWaveBootApp> createState() => _NoWaveBootAppState();
}

class _NoWaveBootAppState extends State<NoWaveBootApp> {
  final Completer<void> _booted = Completer<void>();

  bool _ready = false;
  bool _curtainGone = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await widget.boot();
    } catch (error, stackTrace) {
      _logBootFailure(error, stackTrace);
      if (!mounted) return;
      setState(() => _failure = '$error');
      return;
    }
    if (!mounted) return;
    if (!_booted.isCompleted) _booted.complete();
    setState(() => _ready = true);
  }

  /// Kept out of the catch block so a logging failure cannot mask the boot
  /// failure that is being reported.
  void _logBootFailure(Object error, StackTrace stackTrace) {
    AppLogger.error('Startup failed', error: error, stackTrace: stackTrace);
  }

  void _handleCurtainFinished() {
    if (!mounted || _curtainGone) return;
    setState(() => _curtainGone = true);
  }

  Widget _buildApp() {
    final builder = widget.appBuilder;
    if (builder != null) return builder();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => serviceLocator<ThemeBloc>()),
        BlocProvider(create: (_) => serviceLocator<LocaleBloc>()),
        BlocProvider(create: (_) => serviceLocator<AuthBloc>()),
        BlocProvider(create: (_) => serviceLocator<AppUserCubit>()),
      ],
      child: const NoWaveApp(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) return StartupFailureApp(message: failure);

    // Both children keep their position across rebuilds: the app is inserted
    // where the ink placeholder was, and the curtain is only removed once it
    // has already left the screen. Inserting the app *behind* the curtain is
    // what makes the lift a reveal instead of a swap.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_ready)
          ExcludeSemantics(
            excluding: !_curtainGone,
            child: IgnorePointer(
              ignoring: !_curtainGone,
              child: _buildApp(),
            ),
          )
        else
          const ColoredBox(color: AppPalette.ink),
        if (!_curtainGone) _curtain(),
      ],
    );
  }

  /// The curtain needs its own localization scope: the app's `LocaleBloc` has
  /// not necessarily been restored yet, and its catalogs must not be read
  /// through a router that does not exist yet.
  Widget _curtain() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _curtainTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: resolveAppLocale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: NoWaveSplashScreen(
        ready: _booted.future,
        onFinished: _handleCurtainFinished,
      ),
    );
  }
}

/// Ink, paper and one orange accent - the only theme the curtain needs.
final ThemeData _curtainTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: AppPalette.orange,
    onPrimary: AppPalette.paper,
    secondary: AppPalette.orange,
    surface: AppPalette.ink,
    onSurface: AppPalette.paper,
    error: AppPalette.errorOnInk,
    onError: AppPalette.ink,
  ),
  scaffoldBackgroundColor: AppPalette.ink,
);
