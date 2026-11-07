import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// Keeps the loading-state rule from eroding: no page or section may show a
/// spinner again.
///
/// The design rule is that no-wave prints. A rotating indicator is the one
/// element on screen that belongs to no typeface and no palette, and it cannot
/// say *what* is being waited for. Pages and sections therefore use
/// `NoWaveLoadingLabel` (a rule and a sentence) or `NoWaveSkeleton*` (the shape
/// of the content).
///
/// Two kinds of exception are allowed, and both are enumerated here rather than
/// inferred from the source:
///
/// - **Inside a control.** `NoWaveButton(isLoading: true)` uses a small spinner
///   in the slot where the label already is, and two pages put one in an icon
///   slot. A sentence does not fit in an icon.
/// - **The cold-start curtain** deliberately asserts the *absence* of one.
void main() {
  /// `path: <why a spinner is still the right answer here>`
  const allowed = <String, String>{
    'lib/core/design/components/no_wave_button.dart':
        'the busy state of a button, in the slot its own label keeps',
    'lib/features/blog/presentation/pages/recycle_bin_page.dart':
        'the "restoring" state of one row action, in an icon-sized slot',
    'lib/features/messages/presentation/pages/message_thread_page.dart':
        'the sending state of the send IconButton',
  };

  test('pages and sections do not spin', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (allowed.containsKey(file.path)) continue;
      final hits = _spinnerLines(file);
      if (hits.isEmpty) continue;
      offenders.addAll(hits);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'loading states are a rule and a sentence (NoWaveLoadingLabel) or '
          'the shape of the content (NoWaveSkeleton), not a spinner:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the allowlist does not outlive the code it excuses', () {
    final stale = <String>[];
    for (final path in allowed.keys) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (deleted)');
        continue;
      }
      if (_spinnerLines(file).isEmpty) stale.add('$path (no spinner left)');
    }
    expect(stale, isEmpty, reason: 'drop these entries: $stale');
  });

  test('the scan can see a spinner at all', () {
    // A pattern that matches nothing would pass forever.
    expect(_spinnerLinesOf('CircularProgressIndicator()'), hasLength(1));
    expect(_spinnerLinesOf('CupertinoActivityIndicator()'), hasLength(1));
    expect(_spinnerLinesOf('NoWaveLoadingLabel()'), isEmpty);
  });
}

const _spinners = [
  'CircularProgressIndicator',
  'CupertinoActivityIndicator',
  'LinearProgressIndicator',
];

/// `path:line: <source>` for every spinner call under [file].
List<String> _spinnerLines(File file) =>
    _spinnerLinesOf(file.readAsStringSync(), path: file.path);

List<String> _spinnerLinesOf(String source, {String? path}) {
  final hits = <String>[];
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) continue;
    if (!_spinners.any(line.contains)) continue;
    hits.add(path == null ? line : '$path:${index + 1}: $trimmed');
  }
  return hits;
}
