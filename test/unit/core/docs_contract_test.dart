import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the three living documents honest about the code they describe.
///
/// `docs/design-system.md`, `docs/accessibility.md` and `docs/startup.md` are
/// the only place that says how the UI is supposed to behave, and every phase
/// so far has changed both. A path in prose that points at a deleted file, a
/// component nobody catalogued or a token nobody wrote down is how a design
/// system starts lying: the rule stays readable while the code moves on.
///
/// Historical documents (`code-audit`, `issue-errata`, the dated review
/// snapshots) are deliberately out of scope - they record what was true on a
/// day, and rewriting them would destroy the record.
void main() {
  const living = [
    'docs/design-system.md',
    'docs/accessibility.md',
    'docs/startup.md',
  ];

  /// Directories whose contents are generated or vendored, not authored here.
  const skipped = {
    '.git',
    '.dart_tool',
    '.idea',
    '.gradle',
    '.arena',
    'build',
    'Pods',
    'node_modules',
  };

  final files = <String>[];
  for (final entity in Directory('.').listSync(recursive: true)) {
    if (entity is! File) continue;
    if (entity.path.split(Platform.pathSeparator).any(skipped.contains)) {
      continue;
    }
    files.add(
      entity.path
          .replaceAll(Platform.pathSeparator, '/')
          .replaceFirst(RegExp(r'^\./'), ''),
    );
  }

  final names = <String>{for (final path in files) path.split('/').last};

  /// A reference resolves by full path, by path tail, or by bare filename -
  /// documents say `no_wave_button.dart` as often as the whole path.
  bool resolves(String ref) =>
      files.contains(ref) ||
      names.contains(ref) ||
      files.any((path) => path.endsWith('/$ref'));

  final reference = RegExp(
    r'`([A-Za-z0-9_./-]+\.'
    r'(?:dart|jpg|png|yaml|arb|xml|storyboard|md|sh|txt|plist))`',
  );

  test('every file the documents name still exists', () {
    final broken = <String>[];
    for (final doc in living) {
      final source = File(doc).readAsStringSync();
      for (final match in reference.allMatches(source)) {
        final ref = match.group(1)!;
        if (!resolves(ref)) broken.add('$doc: $ref');
      }
    }
    expect(
      broken,
      isEmpty,
      reason:
          'These references point at nothing. Rename the mention with the '
          'file, or drop it:\n${broken.join('\n')}',
    );
  });

  test('every design component is catalogued', () {
    final doc = File('docs/design-system.md').readAsStringSync();
    final components = Directory(
      'lib/core/design/components',
    ).listSync().whereType<File>();
    final missing = <String>[];
    for (final file in components) {
      final name = file.path.split(Platform.pathSeparator).last;
      if (!doc.contains(name)) missing.add(file.path);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'a component in lib/core/design/components is not in the catalogue '
          'table of docs/design-system.md: ${missing.join(', ')}',
    );
  });

  test('every token is described', () {
    final doc = File('docs/design-system.md').readAsStringSync();
    final source = File(
      'lib/core/design/design_tokens.dart',
    ).readAsStringSync();
    final declaration = RegExp(r'static const (?:\w+(?:<[^>]+>)?\s+)?(\w+) =');
    final classBlock = RegExp(r'abstract final class (\w+) \{([\s\S]*?)\n\}');

    final missing = <String>[];
    var seen = 0;
    for (final block in classBlock.allMatches(source)) {
      for (final token in declaration.allMatches(block.group(2)!)) {
        seen++;
        final name = token.group(1)!;
        if (!doc.contains(name)) missing.add('${block.group(1)}.$name');
      }
    }

    // A scan that stopped seeing tokens would pass forever.
    expect(seen, greaterThan(40), reason: 'the token scan found only $seen');
    expect(
      missing,
      isEmpty,
      reason:
          'a token exists in design_tokens.dart but not in '
          'docs/design-system.md: ${missing.join(', ')}',
    );
  });

  test('living docs describe the current content and avatar URL behavior', () {
    final accessibility = File('docs/accessibility.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(accessibility, contains('content_language.dart'));
    expect(accessibility, contains('`zh-CN`'));
    expect(accessibility, contains('`en`'));
    expect(accessibility, contains('`zh-TW`'));
    expect(accessibility, isNot(contains('请求的语言（仍是 `zh-CN`）')));
    expect(readme, contains('`WEB_BASE_URL`'));
    expect(readme, contains('中性占位'));
    expect(readme, contains('不从 API origin 猜测'));
    expect(readme, isNot(contains('站点相对头像仍待')));
  });

  test('the scan reaches the documents it guards', () {
    for (final doc in living) {
      expect(File(doc).existsSync(), isTrue, reason: '$doc is missing');
    }
    expect(files, isNotEmpty);
  });
}
