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
/// Controls too: a button's busy state, a row action and the send icon had no
/// room for a sentence and kept a small spinner until `NoWaveBusyMark` took
/// their slot - a segment running along a hairline. The allowlist is empty
/// and should stay so; an entry needs a reason no rule or sentence can meet.
///
/// Pull to refresh counts: the stock `RefreshIndicator` (and its `.adaptive`
/// form) drops a spinning disc over the list. Pages use `NoWaveRefresh`, which
/// keeps the gesture through `RefreshIndicator.noSpinner` and draws a rule.
void main() {
  /// `path: <why a spinner is still the right answer here>`
  const allowed = <String, String>{};

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
    expect(_spinnerLinesOf('RefreshIndicator(onRefresh: f)'), hasLength(1));
    expect(
      _spinnerLinesOf('RefreshIndicator.adaptive(onRefresh: f)'),
      hasLength(1),
    );
    expect(
      _spinnerLinesOf('RefreshIndicator.noSpinner(onRefresh: f)'),
      isEmpty,
      reason: 'the gesture without the disc is what NoWaveRefresh builds on',
    );
    expect(_spinnerLinesOf('NoWaveRefresh(onRefresh: f)'), isEmpty);
  });
}

const _spinners = [
  'CircularProgressIndicator',
  'CupertinoActivityIndicator',
  'LinearProgressIndicator',
  'RefreshProgressIndicator',
  'RefreshIndicator(',
  'RefreshIndicator.adaptive(',
  'CupertinoSliverRefreshControl',
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
