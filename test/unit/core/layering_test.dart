import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the dependency direction that #107 established: `lib/core` is the
/// bottom layer, so it may not import a feature, and the persistence code
/// under `lib/core/storage` may not depend on Flutter UI types.
///
/// These rules used to be conventions documented in `docs/code-audit.md`; a
/// source scan makes a regression fail the suite instead of quietly
/// reintroducing the reverse dependency.
void main() {
  test('lib/core never imports a feature', () {
    final offenders = _importsOf('lib/core', (uri) {
      return uri.startsWith('package:belog/features/');
    });
    expect(
      offenders,
      isEmpty,
      reason:
          'lib/core must stay independent of lib/features (#107):\n'
          '${offenders.join('\n')}',
    );
  });

  test('the storage layer never imports Flutter', () {
    final offenders = _importsOf('lib/core/storage', (uri) {
      return uri.startsWith('package:flutter/');
    });
    expect(
      offenders,
      isEmpty,
      reason:
          'lib/core/storage must hold plain Dart types only (#107); a UI '
          'type in a storage port has to be mapped by the caller:\n'
          '${offenders.join('\n')}',
    );
  });

  test('storage ports carry no Flutter UI type', () {
    // A persisted preference is plain data (#107): the theme port stores
    // `AppThemeMode` instead of Flutter's `ThemeMode`, so nothing below the UI
    // needs a widget import. Plugin packages such as flutter_secure_storage
    // are fine - they are not UI types.
    const uiLibraries = [
      'package:flutter/material.dart',
      'package:flutter/widgets.dart',
      'package:flutter/cupertino.dart',
    ];
    final ports = _dartFiles(
      'lib/core',
    ).where((file) => file.path.endsWith('_store.dart')).toList();
    expect(ports, isNotEmpty);
    final offenders = <String>[];
    for (final file in ports) {
      for (final line in file.readAsLinesSync()) {
        final directive = line.trimLeft();
        if (!_isDirective(directive)) continue;
        final uri = _uriOf(directive);
        if (uri != null && uiLibraries.contains(uri)) {
          offenders.add('${file.path}: $directive');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a storage port in lib/core must not depend on Flutter UI '
          'types (#107); map to the UI type at the caller instead:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the scan reaches the files it is meant to guard', () {
    // A guard that silently matches nothing would pass forever.
    expect(_dartFiles('lib/core'), isNotEmpty);
    expect(_dartFiles('lib/core/storage'), isNotEmpty);
  });
}

/// Every `import`/`export`/`part` line under [directory] whose URI matches
/// [isWanted], rendered as `path: directive` for the failure message.
List<String> _importsOf(String directory, bool Function(String uri) isWanted) {
  final offenders = <String>[];
  for (final file in _dartFiles(directory)) {
    for (final line in file.readAsLinesSync()) {
      final directive = line.trimLeft();
      if (!_isDirective(directive)) continue;
      final uri = _uriOf(directive);
      if (uri != null && isWanted(uri)) {
        offenders.add('${file.path}: $directive');
      }
    }
  }
  offenders.sort();
  return offenders;
}

bool _isDirective(String line) =>
    line.startsWith('import ') ||
    line.startsWith('export ') ||
    line.startsWith('part ');

String? _uriOf(String directive) {
  final start = directive.indexOf("'");
  final end = directive.lastIndexOf("'");
  if (start < 0 || end <= start) return null;
  return directive.substring(start + 1, end);
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
