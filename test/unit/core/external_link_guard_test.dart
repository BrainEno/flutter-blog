// Keeps the URL whitelist in front of every address this app hands to the OS.
//
// Article links, covers, avatars and the read-aloud follow all resolve through
// `resolveArticleResourceUrl`, yet the author page launched the profile's
// `websiteUrl` after checking only `hasScheme` - enough for `javascript:` or
// `intent:` to leave the app. Fixing that one call site is worth little unless
// the shape is checked: a second launcher added later should fail this suite
// rather than become the next exception.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// The helper defines the rule instead of applying it.
const _definer = 'lib/core/utils/article_resource_url.dart';

/// Addresses that never arrive from a server: the about page opens
/// compiled-in constants, so there is nothing untrusted to resolve there.
const _ownConstants = <String>{
  'lib/features/user/presentation/pages/about_page.dart',
};

void main() {
  List<String> launchesWithoutWhitelist() {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      if (path == _definer) continue;
      if (_ownConstants.contains(path)) continue;
      final source = file.readAsStringSync();
      if (!source.contains('launchUrl(')) continue;
      if (source.contains('resolveArticleResourceUrl(')) continue;
      if (source.contains('isValidArticleResourceUrl(')) continue;
      hits.add(path);
    }
    return hits;
  }

  test('every launcher call site consults the URL whitelist', () {
    final hits = launchesWithoutWhitelist();
    expect(
      hits,
      isEmpty,
      reason:
          'open only http(s): resolve the value with '
          'resolveArticleResourceUrl and keep the widget inert when it '
          'returns null:\n${hits.join('\n')}',
    );
  });

  test('the scan reaches the files it protects', () {
    // A rule whose scope or allowlist entry vanished would pass forever.
    for (final path in <String>[
      _definer,
      ..._ownConstants,
      'lib/features/blog/presentation/markdown/markdown_renderer.dart',
      'lib/features/user/presentation/pages/author_page.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(dartFilesUnder('lib').length, greaterThan(100));
  });
}
