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
/// resolved anywhere in `lib/` is at least *mentioned* in the wiring - the
/// composition root plus the feature modules under `lib/di/` (#304) - which is
/// what a missing registration always violates. The proof that each
/// registration actually resolves is `test/unit/di/app_modules_test.dart`.
void main() {
  test('every type the app resolves is wired up by the DI modules', () {
    final wiring = _wiringSource();
    final missing = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (_isWiring(file)) continue;
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

  test('init_dependencies stays a composition root (#304)', () {
    final root = File('lib/init_dependencies.dart').readAsLinesSync();
    expect(
      root.length,
      lessThanOrEqualTo(150),
      reason:
          'feature registrations belong in a module under lib/di/, not in '
          'the composition root',
    );
    final registrations = root
        .where((line) => line.contains(RegExp(r'\.register\w*[<(]')))
        .toList();
    expect(
      registrations,
      hasLength(1),
      reason:
          'only the eager ConnectionChecker (which owns the shared HTTP '
          'client) is registered by the root: $registrations',
    );
    expect(
      registrations.single,
      contains('registerSingleton<ConnectionChecker>'),
    );
  });

  test('the scan reaches the files it is meant to guard', () {
    final wiring = _wiringSource();
    expect(wiring.contains('registerFactory'), isTrue);
    expect(dartFilesUnder('lib/di').length, greaterThan(5));
    expect(dartFilesUnder('lib').length, greaterThan(50));
    // The guard must still be able to see a resolution site.
    expect(
      _resolvedType('      final useCase = GetIt.instance<SomeUseCase>();'),
      'SomeUseCase',
    );
  });
}

/// Whether [file] composes the container rather than consuming it.
bool _isWiring(File file) {
  final path = file.path.replaceAll(Platform.pathSeparator, '/');
  return path.endsWith('lib/init_dependencies.dart') ||
      path.contains('lib/di/');
}

/// The composition root and every feature module, concatenated.
String _wiringSource() => [
  File('lib/init_dependencies.dart'),
  ...dartFilesUnder('lib/di'),
].map((file) => file.readAsStringSync()).join('\n');

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
