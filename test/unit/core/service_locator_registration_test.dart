import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// A type the app resolves from the container but never registered throws at the
/// moment a page is built - the 2026-11-05 red screen: the article page asked
/// for `GetRelatedArticles`, which `init_dependencies.dart` had never wired up.
/// Widget tests did not catch it because each of them registers its own little
/// container (`test/widget/router_test.dart` registered exactly that use case),
/// so the app's own wiring was never exercised.
///
/// This is a smoke guard, not a dependency-graph proof: it asserts that a type
/// resolved anywhere in `lib/` is at least *mentioned* in the file that composes
/// the container, which is what a missing registration always violates.
void main() {
  test('every type the app resolves is wired up by init_dependencies', () {
    final wiring = File('lib/init_dependencies.dart').readAsStringSync();
    final missing = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.path.endsWith('init_dependencies.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final type = _resolvedType(lines[index]);
        if (type == null) continue;
        if (!wiring.contains(type)) {
          missing.add('${file.path}:${index + 1}: $type');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'these types are resolved from the service locator but never '
          'registered, so the page that needs them throws at build time:\n'
          '${missing.join('\n')}',
    );
  });

  test('the scan reaches the files it is meant to guard', () {
    final init = File('lib/init_dependencies.dart').readAsStringSync();
    expect(init.contains('registerFactory'), isTrue);
    expect(dartFilesUnder('lib').length, greaterThan(50));
    // The guard must still be able to see a resolution site.
    expect(
      _resolvedType('      final useCase = GetIt.instance<SomeUseCase>();'),
      'SomeUseCase',
    );
  });
}

/// The type resolved by a `serviceLocator<T>()` / `GetIt.instance<T>()` call on
/// [line], or null when the line resolves nothing.
///
/// `isRegistered<T>()` is a capability check, not a resolution, so it is
/// skipped - that is exactly how an optional dependency is meant to be probed.
String? _resolvedType(String line) {
  if (line.contains('.isRegistered<')) return null;
  final match = RegExp(
    r'(?:serviceLocator|GetIt\.instance|GetIt\.I|sl)<([A-Za-z0-9_]+)>\(',
  ).firstMatch(line);
  return match?.group(1);
}
