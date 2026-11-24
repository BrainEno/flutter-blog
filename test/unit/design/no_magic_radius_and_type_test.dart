import 'dart:io';

import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// Corner radii and font sizes a screen should have taken from `NoWaveRadius`
/// and `NoWaveTypeScale` (#294).
///
/// `no_magic_numbers_test.dart` already holds spacing at zero literals. This is
/// the same gate for the two kinds of number it did not cover: a
/// `BorderRadius.circular(12)` or a `fontSize: 15` in a page is a design
/// decision made in the wrong file. Only the token and theme layers
/// (`lib/core/design/`, `lib/core/theme/`) may write those numbers.
///
/// The same goes for a number handed to a `NoWaveTypography` builder as its
/// `size:` - `NoWaveTypography.title(context, size: 24)` is a `fontSize: 24`
/// one call removed, and the line-based `fontSize:` scan cannot see it.
///
/// A genuine one-off is allowed on the line itself with a
/// `design-token-ok: <reason>` marker, exactly like the spacing gate.
void main() {
  /// The layers whose job is to define these numbers.
  const owners = ['lib/core/design/', 'lib/core/theme/'];

  final files = dartFilesUnder('lib')
      .map((file) => file.path.replaceAll('\\', '/'))
      .where((path) => !owners.any(path.startsWith))
      .toList();

  test('no screen writes a literal corner radius', () {
    final offenders = _offenders(files, _radiusLiteral);
    expect(
      offenders,
      isEmpty,
      reason:
          'use a NoWaveRadius token (or add one to design_tokens.dart and '
          'docs/design-system.md):\n${offenders.join('\n')}',
    );
  });

  test('no screen writes a literal font size', () {
    final offenders = _offenders(files, _fontSizeLiteral);
    expect(
      offenders,
      isEmpty,
      reason:
          'use a theme text role or a NoWaveTypeScale token:\n'
          '${offenders.join('\n')}',
    );
  });

  test('no screen hands a literal size to NoWaveTypography', () {
    final offenders = [
      for (final path in files)
        for (final hit in _typographySizeLiterals(
          File(path).readAsStringSync(),
        ))
          '$path:$hit',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'pass a NoWaveTypeScale token as size: (or add one to '
          'design_tokens.dart and docs/design-system.md):\n'
          '${offenders.join('\n')}',
    );
  });

  test('the typography scan sees calls on one line and across lines', () {
    expect(
      _typographySizeLiterals('x = NoWaveTypography.title(context, size: 24);'),
      ['1: x = NoWaveTypography.title(context, size: 24);'],
    );
    expect(
      _typographySizeLiterals(
        'a(\n  NoWaveTypography.title(\n    context,\n    size: 32.5,\n  ),\n)',
      ),
      ['4: size: 32.5,'],
    );
    expect(
      _typographySizeLiterals(
        'NoWaveTypography.title(context, size: NoWaveTypeScale.rowTitle)',
      ),
      isEmpty,
    );
    expect(
      _typographySizeLiterals(
        'NoWaveTypography.display(context, size: size, color: c)',
      ),
      isEmpty,
    );
    expect(
      _typographySizeLiterals(
        'NoWaveTypography.title(context, size: 21), // design-token-ok: why',
      ),
      isEmpty,
    );
    expect(
      _typographySizeLiterals('// NoWaveTypography.title(context, size: 24)'),
      isEmpty,
    );
    // A size outside the builder's own parentheses is someone else's.
    expect(
      _typographySizeLiterals(
        'NoWaveTypography.title(context); Icon(i, size: 20);',
      ),
      isEmpty,
    );
  });

  test('the scan sees the shapes it is meant to catch', () {
    expect(_radiusLiteral.hasMatch('BorderRadius.circular(12)'), isTrue);
    expect(_radiusLiteral.hasMatch('const Radius.circular(8.5)'), isTrue);
    expect(_radiusLiteral.hasMatch('Radius.elliptical(4, 2)'), isTrue);
    expect(
      _radiusLiteral.hasMatch('BorderRadius.circular(NoWaveRadius.surface)'),
      isFalse,
    );
    expect(_fontSizeLiteral.hasMatch('fontSize: 15,'), isTrue);
    expect(_fontSizeLiteral.hasMatch('TextStyle(fontSize: 13.5)'), isTrue);
    expect(
      _fontSizeLiteral.hasMatch('fontSize: NoWaveTypeScale.label'),
      isFalse,
    );
    expect(files.length, greaterThan(100), reason: 'the scan lost its scope');
  });

  group('the rounded steps', () {
    test('grow in order from square to stadium', () {
      const steps = [
        NoWaveRadius.none,
        NoWaveRadius.badge,
        NoWaveRadius.inline,
        NoWaveRadius.thumbnail,
        NoWaveRadius.surface,
        NoWaveRadius.container,
        NoWaveRadius.pill,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]));
      }
    });

    test('pill stays a stadium for any badge the text scale can produce', () {
      // A count badge at 3x text is still far below 2 * pill, so the
      // rounded-rectangle clamp always resolves to half the badge height.
      expect(NoWaveRadius.pill * 2, greaterThan(200));
    });

    test('keep the values the screens rendered before the tokens', () {
      // #294 named existing corners; it did not restyle them. A change here
      // is a visual change and needs its own decision and screenshots.
      expect(NoWaveRadius.inline, 4);
      expect(NoWaveRadius.thumbnail, 6);
      expect(NoWaveRadius.surface, 8);
      expect(NoWaveRadius.container, 12);
    });
  });

  group('the direct type sizes', () {
    test('are ordered and keep their pre-token values', () {
      const sizes = [
        NoWaveTypeScale.codeBlock,
        NoWaveTypeScale.codeInline,
        NoWaveTypeScale.label,
        NoWaveTypeScale.hint,
        NoWaveTypeScale.sectionTitle,
      ];
      expect(sizes, [13, 14, 15, 17, 18]);
    });

    test('the list and page titles keep the values the pages drew', () {
      // #294 moved these out of `NoWaveTypography.title(size: <n>)` calls; it
      // did not resize anything.
      expect(NoWaveTypeScale.pageTitle, 32);
      expect(NoWaveTypeScale.leadTitle, 30);
      expect(NoWaveTypeScale.rowTitle, 24);
      expect(NoWaveTypeScale.searchQuery, 24);
      expect(NoWaveTypeScale.entryTitle, 20);
      expect(NoWaveTypeScale.gridTitle, 19);
      // A secondary entry stays under an article row, and a page about one
      // thing stays under a list page's heading.
      expect(NoWaveTypeScale.entryTitle, lessThan(NoWaveTypeScale.rowTitle));
      expect(NoWaveTypeScale.pageTitle, lessThan(NoWaveTypeScale.heading));
    });

    test('body headings step down by level', () {
      const levels = [
        NoWaveTypeScale.bodyHeading1,
        NoWaveTypeScale.bodyHeading2,
        NoWaveTypeScale.bodyHeading3,
        NoWaveTypeScale.bodyHeading4,
      ];
      expect(levels, [26, 22, 19, 17]);
    });
  });
}

/// `Radius.circular(<number>` / `Radius.elliptical(<number>` (which also
/// covers `BorderRadius.circular`).
final _radiusLiteral = RegExp(r'Radius\.(?:circular|elliptical)\(\s*[0-9]');

/// `fontSize: <number>`.
final _fontSizeLiteral = RegExp(r'\bfontSize:\s*[0-9]');

/// A `NoWaveTypography.<builder>(` call.
final _typographyCall = RegExp(r'NoWaveTypography\.\w+\(');

/// A `size:` argument given a number.
final _sizeLiteral = RegExp(r'\bsize:\s*[0-9]');

/// `line: text` for every `size: <number>` inside the parentheses of a
/// `NoWaveTypography` builder call in [source], on a non-comment line without
/// a `design-token-ok` marker. Calls may span lines.
List<String> _typographySizeLiterals(String source) {
  final lines = source.split('\n');
  int lineOf(int offset) => '\n'.allMatches(source.substring(0, offset)).length;
  final hits = <String>[];
  for (final call in _typographyCall.allMatches(source)) {
    if (lines[lineOf(call.start)].trimLeft().startsWith('//')) continue;
    var depth = 1;
    var end = call.end;
    while (end < source.length && depth > 0) {
      final char = source[end];
      if (char == '(') depth++;
      if (char == ')') depth--;
      end++;
    }
    final arguments = source.substring(call.end, end);
    for (final size in _sizeLiteral.allMatches(arguments)) {
      final line = lines[lineOf(call.end + size.start)];
      if (line.trimLeft().startsWith('//')) continue;
      if (line.contains('design-token-ok')) continue;
      hits.add('${lineOf(call.end + size.start) + 1}: ${line.trim()}');
    }
  }
  return hits;
}

/// `path:line: text` for every non-comment, unmarked line matching [pattern].
List<String> _offenders(List<String> paths, RegExp pattern) {
  final offenders = <String>[];
  for (final path in paths) {
    final lines = File(path).readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.trimLeft().startsWith('//')) continue;
      if (line.contains('design-token-ok')) continue;
      if (pattern.hasMatch(line)) {
        offenders.add('$path:${index + 1}: ${line.trim()}');
      }
    }
  }
  return offenders;
}
