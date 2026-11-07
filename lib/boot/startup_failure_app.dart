import 'package:belog/core/common/widgets/no_wave_wordmark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// The app's first frame when startup configuration is unusable.
///
/// `initDependencies` validates `API_BASE_URL` and opens local storage. An
/// exception there used to end `main` with nothing on screen - a blank window
/// and one console line - which reads as "the app is broken" rather than "the
/// config is missing". Saying why and how to fix it is this screen's whole job.
///
/// It deliberately depends on nothing from the injector: the injector is what
/// failed. It is also the one screen that prints both languages at once, since
/// the locale preference and the ARB delegates may not have run either - see
/// the allowlist note in `test/unit/core/ui_copy_literals_test.dart`.
///
/// The palette is the brand's, not Material's: ink paper and orange, square
/// corners. A purple Material default here would read as a different app at the
/// exact moment the user is already worried.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});

  /// Why startup stopped. Text from our own validation or a storage error;
  /// client configuration carries no secrets by contract.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return MaterialApp(
      title: 'No Wave',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: AppPalette.ink,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(NoWaveSpacing.large),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const NoWaveWordmark(
                      size: NoWaveSizes.splashWordmark,
                      color: AppPalette.paper,
                    ),
                    const SizedBox(height: NoWaveSpacing.section),
                    Text(
                      '无法启动 · Unable to start',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: NoWaveSpacing.small),
                    SelectableText(message, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: NoWaveSpacing.large),
                    Text(
                      '复制 env.example.json 为 env.json，填入模拟器或真机可访问的 '
                      'API_BASE_URL 后重新运行；也可以直接使用 '
                      'scripts/run_android.cmd 或 scripts/run_ios.sh。',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: NoWaveSpacing.small),
                    const SelectableText(
                      'flutter run --debug --dart-define-from-file=env.json',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: AppPalette.mutedOnInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paper on ink, one accent. No seed colour: a generated scheme is exactly how
/// the purple got in.
final ThemeData _theme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: AppPalette.orange,
    onPrimary: AppPalette.ink,
    secondary: AppPalette.orange,
    surface: AppPalette.ink,
    onSurface: AppPalette.paper,
    error: AppPalette.errorOnInk,
    onError: AppPalette.ink,
  ),
  scaffoldBackgroundColor: AppPalette.ink,
  textTheme: const TextTheme(
    headlineSmall: TextStyle(color: AppPalette.paper),
    bodyMedium: TextStyle(color: AppPalette.paper),
  ),
);
