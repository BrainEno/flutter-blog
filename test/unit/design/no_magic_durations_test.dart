import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// Keeps the motion system from dissolving back into per-screen numbers.
///
/// A duration is one of two things: how the app moves, or how long the app
/// waits. Only the second belongs in the file that waits - a request timeout, a
/// retry backoff, an autosave dwell, an input debounce. The first must come from
/// `NoWaveMotion`, because a fade that lasts 200ms on one screen and 300 on the
/// next is the kind of drift nobody files a bug for and every reader feels.
///
/// The allowance is file-level rather than line-level: a file whose job is
/// waiting has a reason, and the reason is worth writing down once. Anything
/// else reads a token - `NoWaveMotion.normal`, or a `NoWaveMotionPolicy`
/// resolution of it, which is also what turns the duration into a jump when the
/// reader asked for less motion.
void main() {
  /// Files whose durations are waiting, not motion. Keep the reason next to the
  /// path: a future reader has to be able to tell whether a new duration is the
  /// same kind of thing.
  ///
  /// Since #295 a new wait does not earn its own entry here: it becomes a
  /// named constant in `core/config/app_durations.dart`, and the file that
  /// waits reads it. The other entries compute a duration rather than
  /// configure one.
  const waiting = <String, String>{
    'core/design/design_tokens.dart': 'the tokens themselves',
    'core/config/app_durations.dart':
        'every configured wait: timeouts, debounces, dwell, retention (#295)',
    'core/utils/retry_on_connection_closed.dart':
        'jitter computed from the configured initial delay',
    'features/blog/data/datasources/latest_feed_cursor.dart':
        'cursor arithmetic: one millisecond of inclusive bound',
    'features/blog/presentation/read_aloud/read_aloud_sleep_timer.dart':
        'the sleep-timer menu choices, which are product copy',
  };

  /// `Duration(milliseconds: 200)` and friends.
  final literal = RegExp(
    r'Duration\(\s*(?:microseconds|milliseconds|seconds|minutes|hours)\s*:',
  );

  final files =
      dartFilesUnder('lib')
          .map((file) => file.path.replaceAll(Platform.pathSeparator, '/'))
          .map((path) => path.replaceFirst('lib/', ''))
          .toList()
        ..sort();

  /// How many durations [path] writes itself; 0 when it reads tokens.
  int literalsIn(String path) =>
      literal.allMatches(File('lib/$path').readAsStringSync()).length;

  test('motion reads NoWaveMotion, not its own durations', () {
    final offenders = [
      for (final path in files)
        if (!waiting.containsKey(path) && literalsIn(path) > 0)
          '$path (${literalsIn(path)})',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'These files invent an animation duration. Read NoWaveMotion - and '
          'NoWaveMotionPolicy when the value depends on less-motion: '
          '${offenders.join(', ')}',
    );
  });

  test('the allowance does not point at files that no longer wait', () {
    final stale = [
      for (final path in waiting.keys)
        if (!File('lib/$path').existsSync() || literalsIn(path) == 0) path,
    ];
    expect(
      stale,
      isEmpty,
      reason: 'Drop these from the allowance: ${stale.join(', ')}',
    );
  });

  test('the scan can still see a duration', () {
    // A gate that silently matches nothing is worse than no gate.
    expect(literalsIn('core/design/design_tokens.dart'), greaterThan(0));
    expect(literalsIn('core/config/app_durations.dart'), greaterThan(0));
  });

  test('pages never configure a wait of their own (#295)', () {
    // The narrower rule from the issue: a screen reads AppDurations or a
    // motion token, it never writes a duration, not even an allowed one.
    final pages = [
      for (final path in files)
        if (path.contains('/pages/') && literalsIn(path) > 0) path,
    ];
    expect(
      pages,
      isEmpty,
      reason:
          'Move these waits into core/config/app_durations.dart: '
          '${pages.join(', ')}',
    );
  });
}
