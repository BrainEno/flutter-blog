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
  });
}

/// `Radius.circular(<number>` / `Radius.elliptical(<number>` (which also
/// covers `BorderRadius.circular`).
final _radiusLiteral = RegExp(r'Radius\.(?:circular|elliptical)\(\s*[0-9]');

/// `fontSize: <number>`.
final _fontSizeLiteral = RegExp(r'\bfontSize:\s*[0-9]');

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
