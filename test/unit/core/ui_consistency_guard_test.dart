import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// Keeps three shared helpers the only way to do their job.
///
/// Each rule replaced copies that had already started to drift: snackbars
/// with different durations and queueing (#293), a sessions page with its own
/// date shape (#303) and three hand-rolled 300ms search timers (#292). A
/// source scan makes a fourth copy fail the suite instead of quietly
/// reintroducing the inconsistency.
void main() {
  /// The generated localization classes are not authored here.
  bool authored(File file) => !file.path.startsWith('lib/l10n/');

  List<String> offenders(Pattern pattern, Set<String> allowed) {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib').where(authored)) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      if (allowed.contains(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (line.contains(pattern)) hits.add('$path:${i + 1}: $line');
      }
    }
    return hits;
  }

  test('pages show feedback through showSnackBar only', () {
    final hits = offenders('ScaffoldMessenger.of(', {
      'lib/core/utils/show_snackbar.dart',
    });
    expect(
      hits,
      isEmpty,
      reason:
          'use showSnackBar(context, message) from '
          'lib/core/utils/show_snackbar.dart (#293); pass `duration:` when a '
          'message needs a different display time:\n${hits.join('\n')}',
    );
  });

  test('dates are formatted by formatDate only', () {
    final hits = offenders('DateFormat.', {'lib/core/utils/format_date.dart'});
    expect(
      hits,
      isEmpty,
      reason:
          'use formatDate(locale, date) from lib/core/utils/format_date.dart '
          '(#303); pass `withTime: true` when the time of day matters:\n'
          '${hits.join('\n')}',
    );
  });

  test('search boxes share one debounce', () {
    // The value itself lives with the other configured waits (#295);
    // search_debounce.dart re-exports it as kSearchDebounceDelay.
    final hits = offenders(RegExp(r'Duration\(milliseconds: 300\)'), {
      'lib/core/config/app_durations.dart',
    });
    expect(
      hits,
      isEmpty,
      reason:
          'use SearchDebounce / kSearchDebounceDelay from '
          'lib/core/utils/search_debounce.dart (#292):\n${hits.join('\n')}',
    );
  });

  test('page titles start on the gutter, set once in the theme', () {
    // appBarTheme sets centerTitle: false next to titleSpacing; a page that
    // centres its own title puts it on a different axis from the masthead.
    final hits = offenders(RegExp(r'centerTitle:'), {
      'lib/core/theme/theme.dart',
    });
    expect(
      hits,
      isEmpty,
      reason:
          'leave the title alignment to appBarTheme in '
          'lib/core/theme/theme.dart:\n${hits.join('\n')}',
    );
  });

  test('the scan reaches the helpers it protects', () {
    // A rule whose allowlisted file vanished would pass forever.
    for (final path in const [
      'lib/core/utils/show_snackbar.dart',
      'lib/core/utils/format_date.dart',
      'lib/core/utils/search_debounce.dart',
      'lib/core/config/app_durations.dart',
      'lib/core/theme/theme.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(dartFilesUnder('lib').where(authored).length, greaterThan(100));
  });
}
