import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// Keeps navigation addresses in `lib/router/route_paths.dart` (#295).
///
/// Before #295 the router declared 30 `path:` literals and pages wrote about
/// 60 location strings by hand; renaming one route meant a search across every
/// feature, and a single forgotten `Uri.encodeComponent` let an id with a `/`
/// open the wrong page. A page now asks `RoutePaths` for a location. This scan
/// rejects a navigation call whose first argument is a string literal that
/// starts with `/`, which is the shape every hand-written location had.
void main() {
  /// `context.push('/…')`, `context.go<bool>("/…")`, `router.replace('/…')`.
  final literalNavigation = RegExp(
    r'''\.(?:push|go|pushReplacement|replace)(?:<[^>()]*>)?\(\s*['"]/''',
  );

  /// The one file allowed to spell out locations.
  const owner = 'lib/router/route_paths.dart';

  List<String> offendersIn(String source, String path) => [
    for (final match in literalNavigation.allMatches(source))
      '$path:${'\n'.allMatches(source.substring(0, match.start)).length + 1}',
  ];

  test('pages navigate through RoutePaths, never a location literal', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      if (path == owner) continue;
      offenders.addAll(offendersIn(file.readAsStringSync(), path));
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use a RoutePaths constant or builder instead of a location '
          'literal: ${offenders.join(', ')}',
    );
  });

  test('the scan still recognises the shapes it is meant to reject', () {
    // A gate that silently matches nothing is worse than no gate.
    expect(offendersIn("context.push('/login');", 'a'), hasLength(1));
    expect(offendersIn('context.go("/");', 'a'), hasLength(1));
    expect(
      offendersIn("await context.push<bool>(\n  '/editor',\n);", 'a'),
      hasLength(1),
    );
    expect(offendersIn('context.push(RoutePaths.login);', 'a'), isEmpty);
    expect(offendersIn("client.postJson('/tags', body);", 'a'), isEmpty);
  });
}
