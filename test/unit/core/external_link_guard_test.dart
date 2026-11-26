// Keeps the URL whitelist in front of every address this app hands to the OS.
//
// Article links, covers, avatars and the read-aloud follow all resolve through
// `resolveArticleResourceUrl`, yet the author page launched the profile's
// `websiteUrl` after checking only `hasScheme` - enough for `javascript:` or
// `intent:` to leave the app (issue #369). Fixing that one call site was worth
// little while the shape stayed checkable only by reading every launcher, so
// the check and the hand-off now share one owner: `ArticleResourceOpener`.
//
// Two rules follow from that, and both are about the future rather than today:
// a second `launchUrl(` may not appear anywhere, and a page that opens a
// server-supplied address may not go around the door.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// The only file allowed to talk to `url_launcher`, because it applies the
/// whitelist first and it is the only place that needs the launch mode.
const _door = 'lib/core/utils/article_resource_opener.dart';

/// The whitelist the door defers to; it stays free of plugin imports so the
/// twelve places that only need a resolution decision keep importing that.
const _whitelist = 'lib/core/utils/article_resource_url.dart';

/// Addresses that never arrive from a server: the about page opens compiled-in
/// constants (`mailto:` and the repository URL), which the whitelist would
/// reject and the page must not route around it either.
const _compiledInLinks = <String>{
  'lib/features/user/presentation/pages/about_page.dart',
};

/// Files that open server-supplied addresses, so each one must hold an opener.
const _opensServerAddresses = <String, String>{
  'lib/features/user/presentation/pages/author_page.dart':
      'the websiteUrl on an author profile',
  'lib/features/blog/presentation/markdown/markdown_renderer.dart':
      'a link href inside the article body',
};

void main() {
  /// A file's code lines: comment text is dropped, so a doc comment that names
  /// the plugin is not mistaken for a call site.
  List<String> codeLines(File file) {
    final kept = <String>[];
    for (final line in file.readAsLinesSync()) {
      final text = line.trimLeft();
      if (text.startsWith('//')) continue;
      if (text.startsWith('*')) continue;
      kept.add(line);
    }
    return kept;
  }

  List<String> launcherCallSites() {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      final code = codeLines(file).join('\n');
      if (code.contains('launchUrl(')) hits.add(path);
    }
    return hits;
  }

  test('only the door may hand an address to the platform', () {
    final hits = launcherCallSites();
    expect(
      hits.toSet(),
      {_door, ..._compiledInLinks},
      reason:
          'an address from the server reaches the OS through '
          'ArticleResourceOpener, which applies the whitelist and picks the '
          'launch mode in one place. A new `launchUrl(` call site means either '
          'a page skipped that door (open it with ArticleResourceOpener '
          'instead) or the door moved - update this list in the same commit '
          'and say why:\n${hits.join('\n')}',
    );
  });

  test('a page that opens server-supplied addresses uses the door', () {
    _opensServerAddresses.forEach((path, source) {
      final code = File(path).readAsStringSync();
      expect(
        code.contains('ArticleResourceOpener'),
        isTrue,
        reason:
            '$path opens $source; holding the opener is what keeps the '
            'inert/tappable decision and the launch on one rule, and what lets '
            'a widget test count what would have left the app.',
      );
    });
  });

  test('the scan reaches the files it protects', () {
    // A rule whose scope or allowlist entry vanished would pass forever.
    for (final path in <String>[
      _door,
      _whitelist,
      ..._compiledInLinks,
      ..._opensServerAddresses.keys,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(dartFilesUnder('lib').length, greaterThan(100));
  });
}
