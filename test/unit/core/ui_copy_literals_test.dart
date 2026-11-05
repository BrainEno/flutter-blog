import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the copy rule that #24 established: user-facing text comes from the
/// ARB catalogs (`lib/l10n/app_zh.arb` / `app_en.arb`), never from a literal
/// baked into a widget.
///
/// A literal cannot follow the system language and cannot be translated, so a
/// hardcoded string is a silent regression: the Chinese build looks fine and
/// the English one leaks Chinese. `flutter gen-l10n` regenerates
/// `lib/l10n/app_localizations*.dart` from the catalogs, and this scan keeps
/// every other file honest.
///
/// Scope is the *copy sinks* only - the parameters that end up as text on
/// screen. Stored taxonomy values (`editorTagOptions`), error fallbacks in the
/// data layer (`Failure('…')`, which the UI never shows directly because it
/// localizes through `core/l10n/failure_l10n.dart` by stable code) and
/// diagnostics/log text are deliberately out of scope.
void main() {
  test('no widget hardcodes user-facing Chinese copy', () {
    final offenders = <String>[];
    final allowlistedFiles = <String>{};

    for (final file in _dartFiles('lib')) {
      if (file.path.startsWith('lib/l10n/')) continue; // catalogs + generated
      final hits = _hardcodedCopyIn(file);
      if (hits.isEmpty) continue;
      if (_allowlist.containsKey(file.path)) {
        allowlistedFiles.add(file.path);
        continue;
      }
      offenders.addAll(hits);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'user-facing copy belongs in lib/l10n/*.arb so it can follow the '
          'system language (#24). Add the message to both catalogs and read '
          'it through `context.l10n`:\n${offenders.join('\n')}',
    );

    // An allowlist entry that no longer matches anything is rot: it hides
    // nothing and would silently bless the next literal with the same path.
    expect(
      allowlistedFiles,
      _allowlist.keys.toSet(),
      reason:
          'a file in the allowlist no longer contains hardcoded copy; remove '
          'it from the allowlist in this test',
    );
  });

  test('the scan reaches the files it is meant to guard', () {
    final files = _dartFiles('lib');
    expect(files.length, greaterThan(100));
    // The scan must be able to see a sink at all: a pattern that matches
    // nothing would pass forever.
    final probe = _hardcodedCopyIn(
      File('test/fixtures/copy_scan_probe.dart.tmp'),
      contents: "Text('硬编码文案');",
    );
    expect(probe, hasLength(1));
  });
}

/// Files that intentionally keep their own copy instead of reading the ARB.
///
/// Keep this list tiny and justify every entry: the point of the guard is that
/// a new hardcoded string fails the suite.
const _allowlist = <String, String>{
  'lib/core/startup/startup_failure_app.dart':
      'Shown when startup fails (missing/invalid env.json, unreadable '
      'storage), which is exactly the state where the locale bloc, the '
      'preference store and the ARB delegates may not have run yet. It '
      'therefore prints both languages at once, and its body is a developer '
      'setup instruction, not product copy.',
};

/// Parameters that render as text, i.e. the places a hardcoded string leaks
/// into the UI. `label`/`title` cover the app's own small widgets.
final _copySink = RegExp(
  r'(?:^|[^A-Za-z0-9_$])'
  r'(?:Text|Text\.rich|SelectableText|TextSpan|Tooltip|tooltip|semanticLabel'
  r'|hintText|labelText|helperText|errorText|label|title)'
  r'\s*[:(]\s*$',
);

final _han = RegExp(r'[\u4e00-\u9fff]');

/// Single-quoted literals, honouring backslash escapes.
final _singleQuoted = RegExp(r"'((?:\\.|[^'\\])*)'");

/// Double-quoted literals, honouring backslash escapes.
final _doubleQuoted = RegExp(r'"((?:\\.|[^"\\])*)"');

/// `path:line: literal` for every Han-containing literal that is passed to a
/// copy sink.
List<String> _hardcodedCopyIn(File file, {String? contents}) {
  final text = contents ?? file.readAsStringSync();
  final offenders = <String>[];
  for (final pattern in [_singleQuoted, _doubleQuoted]) {
    for (final match in pattern.allMatches(text)) {
      final literal = match.group(1) ?? '';
      if (!_han.hasMatch(literal)) continue;
      final before = text
          .substring(match.start < 200 ? 0 : match.start - 200, match.start)
          .trimRight();
      if (!_copySink.hasMatch(before)) continue;
      final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
      offenders.add('${file.path}:$line: $literal');
    }
  }
  offenders.sort();
  return offenders;
}

List<File> _dartFiles(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}
