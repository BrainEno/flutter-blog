import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Numbers a screen should have taken from `NoWaveSpacing` / `NoWaveSizes`.
///
/// The design system only holds if pages stop re-deciding their own gaps. The
/// token file is easy to write and easy to ignore, so this test turns the rule
/// into a gate: spacing literals may only go away, never appear. It scans for
/// the shapes screens actually write - `SizedBox(height: 8)`,
/// `EdgeInsets.all(16)`, `Wrap(spacing: 12)`, a hard-coded `BorderSide` width -
/// and ignores `0`, which is a reset rather than a measurement.
///
/// The budget used to be the frozen state of the tree when the gate landed
/// (358 literals). It is empty now: every screen reads a token, so the gate is
/// absolute - one literal anywhere fails, and the fix is to use a token, not to
/// raise the number. A genuine exception (an optical offset, a one-off glyph
/// size) is allowed on the line itself, where a reviewer cannot miss it:
///
/// ```dart
/// const SizedBox(height: 2), // design-token-ok: baseline nudge
/// ```
///
/// The marker has to sit on the line that carries the number: the scan drops
/// that line, so a marker above a multi-line `EdgeInsets` excuses nothing.
/// Never add one to make a number pass - it is the place to write down why the
/// number is not a step of the scale.
void main() {
  /// Files whose whole job is the design system must not contain any.
  const strict = ['core/design/', 'core/common/widgets/', 'core/theme/'];

  /// Empty on purpose: see the note at the top of this file.
  const budget = <String, int>{};

  // Paths are relative to `lib/`, which keeps the budget readable.
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll(Platform.pathSeparator, '/'))
          .map((path) => path.replaceFirst('lib/', ''))
          .where((path) => path.endsWith('.dart'))
          .toList()
        ..sort();

  test('the design system itself has no spacing literals', () {
    final offenders = <String>[];
    for (final path in files) {
      if (!strict.any(path.startsWith)) continue;
      final count = _spacingLiterals(File('lib/$path').readAsStringSync());
      if (count > 0) offenders.add('$path ($count)');
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Design-system files must read every number from design_tokens.dart; '
          'found spacing literals in: ${offenders.join(', ')}',
    );
  });

  test('no file gained spacing literals', () {
    final grown = <String>[];
    final current = <String, int>{};
    for (final path in files) {
      final count = _spacingLiterals(File('lib/$path').readAsStringSync());
      if (count == 0) continue;
      current[path] = count;
      final allowed = budget[path] ?? 0;
      if (count > allowed) grown.add('$path: $count (budget $allowed)');
    }
    expect(
      grown,
      isEmpty,
      reason:
          'Spacing literals may only be replaced by tokens, never added. '
          'These files grew: ${grown.join(', ')}',
    );
  });

  test('the remaining literals only shrink', () {
    var total = 0;
    for (final path in files) {
      total += _spacingLiterals(File('lib/$path').readAsStringSync());
    }
    // Lower this when a page is migrated; never raise it.
    const ceiling = 0;
    expect(
      total,
      lessThanOrEqualTo(ceiling),
      reason:
          'The tree has $total spacing literals, more than the $ceiling it had '
          'when the gate landed. Use NoWaveSpacing or mark the line with '
          '`design-token-ok`.',
    );
  });

  test('the budget does not point at deleted files', () {
    final missing = budget.keys.where(
      (path) => !File('lib/$path').existsSync(),
    );
    expect(missing, isEmpty, reason: 'Drop these from the budget: $missing');
  });
}

/// Counts non-zero numbers used as spacing, insets, gaps or border widths.
///
/// Deliberately textual: it reads the source the way a reviewer does. A number
/// is therefore one of three things - a token, a named constant with its own
/// doc comment, or a `design-token-ok` line saying why it is neither.
int _spacingLiterals(String source) {
  final lines = source
      .split('\n')
      .where(
        (line) =>
            !line.trimLeft().startsWith('//') &&
            !line.contains('design-token-ok'),
      )
      .join('\n');
  var total = 0;
  for (final pattern in _patterns) {
    for (final match in pattern.allMatches(lines)) {
      for (final number in _number.allMatches(match.group(1)!)) {
        if (double.parse(number.group(0)!) != 0) total++;
      }
    }
  }
  return total;
}

final _number = RegExp(r'[0-9]+(?:\.[0-9]+)?');

final _patterns = <RegExp>[
  RegExp(r'SizedBox\s*\(\s*(?:width|height):\s*([0-9]+(?:\.[0-9]+)?)'),
  RegExp(r'SizedBox\.square\s*\(\s*size:\s*([0-9]+(?:\.[0-9]+)?)'),
  RegExp(
    r'EdgeInsets(?:Geometry)?\.(?:all|only|symmetric|fromLTRB)\(([^)]*)\)',
  ),
  RegExp(
    r'\b(?:gap|spacing|runSpacing|crossAxisSpacing|mainAxisSpacing|space):'
    r'\s*([0-9]+(?:\.[0-9]+)?)',
  ),
  RegExp(r'BorderSide\([^)]*\bwidth:\s*([0-9]+(?:\.[0-9]+)?)'),
];
