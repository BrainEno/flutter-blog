import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// The app's first frame when startup configuration is unusable.
///
/// `initDependencies` runs before `runApp`: it validates `API_BASE_URL` and
/// opens local storage. An exception there used to end `main` with nothing on
/// screen - a blank window and one console line - which reads as "the app is
/// broken" rather than "the config is missing". Saying why and how to fix it
/// is this screen's whole job.
///
/// It deliberately depends on nothing from the injector: the injector is what
/// failed.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});

  /// Why startup stopped. Text from our own validation or a storage error;
  /// client configuration carries no secrets by contract.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorSchemeSeed: const Color(0xFF7A4FBF),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'No Wave',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
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
                    Icon(
                      Icons.settings_suggest_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: NoWaveSpacing.medium),
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
                      style: TextStyle(fontFamily: 'monospace'),
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
