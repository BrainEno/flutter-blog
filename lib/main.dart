import 'dart:ui' show PlatformDispatcher;

import 'package:belog/boot/no_wave_boot_app.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:flutter/material.dart';

/// Entry point: handlers, then the boot screen, and nothing else.
///
/// Nothing here awaits. Dependency setup, the language preference and the
/// session restore used to run before `runApp`, which kept the OS launch image
/// (and the old project's logo with it) on screen for as long as they took.
/// They now run inside [NoWaveBootApp], behind the cold-start curtain, so the
/// first frame the engine can draw is already the brand.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();
  runApp(const NoWaveBootApp());
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
