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
  const waiting = <String, String>{
    'core/design/design_tokens.dart': 'the tokens themselves',
    'boot/boot_sequence.dart': 'session and language restore timeouts',
    'core/network/api_connection_checker.dart': 'connect timeout',
    'core/nowave/nowave_api_client.dart': 'request and upload timeouts',
    'core/nowave/nowave_session.dart': 'refresh lead time before expiry',
    'core/utils/retry_on_connection_closed.dart': 'retry backoff',
    'features/blog/data/datasources/latest_feed_cursor.dart':
        'cursor arithmetic: one millisecond of inclusive bound',
    'features/blog/data/publish/publish_queue_runner.dart':
        'publish retry schedule',
    'features/blog/presentation/pages/blog_editor_page.dart': 'autosave dwell',
    'features/blog/presentation/pages/search_blog_page.dart':
        'input debounce, and how long a failure notice stays',
    'features/user/presentation/pages/author_search_page.dart':
        'input debounce',
    'features/user/presentation/pages/about_page.dart': 'package info timeout',
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
  });
}
