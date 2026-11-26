// Keeps one owner for the featured shelf's write, and one shape for its body.
//
// `PUT /featured` replaces the whole shelf for one content locale: the server
// merges nothing, refuses a list over `MAX_FEATURED_ARTICLES` or with a
// duplicate, and answers `403` for anyone it does not treat as an editor
// (`docs/featured-curation.md`, issue #377). Two mistakes are cheap to make and
// expensive to ship, so both are now machine-checked rather than reviewed:
//
// - A second writer would be a second copy of the body. The server answers any
//   extra key with `400 The request contains unsupported fields.`, so a
//   hand-rolled `{'articleIds': …, 'locale': …}` fails in a way that reads
//   as the user's fault.
// - A screen that read the shelf through the feed path would see ten works and
//   save ten back. `BlogFeedKind.featured` is paged at the home tab's page
//   size; the shelf holds twenty. That is a silent truncation of another
//   editor's picks, which no test of the screen itself would notice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// The only file allowed to write the shelf, because it is the only one that
/// fences the session, refuses an offline attempt before a body exists, and
/// reads the answer back instead of trusting its own optimistic list.
const _door =
    'lib/features/blog/data/repositories/featured_shelf_repository_impl.dart';

/// The one file allowed to *read* `/featured`: the home tab's feed. Reading is
/// safe at any page size, which is why it is not pulled into the door - but it
/// must stay a reader.
const _featuredReaders = <String>{
  'lib/features/blog/data/datasources/blog_remote_article_reads.dart',
};

/// The screen that arranges the shelf. Naming it here is the point: it must
/// reach the shelf through the door, not through the feed.
const _shelfScreen =
    'lib/features/blog/presentation/pages/featured_shelf_page.dart';

void main() {
  /// Code only: a doc comment that names `PUT /featured` explains the contract,
  /// it does not issue one.
  List<String> codeLines(File file) {
    final kept = <String>[];
    for (final line in file.readAsLinesSync()) {
      final text = line.trimLeft();
      if (text.startsWith('//') || text.startsWith('*')) continue;
      kept.add(line);
    }
    return kept;
  }

  Map<String, String> code() {
    final files = <String, String>{};
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      files[path] = codeLines(file).join('\n');
    }
    return files;
  }

  List<String> mentioning(Map<String, String> files, Pattern needle) {
    final hits = <String>[];
    files.forEach((path, content) {
      if (content.contains(needle)) hits.add(path);
    });
    hits.sort();
    return hits;
  }

  test('only the door may send the shelf body', () {
    final files = code();
    expect(mentioning(files, "'articleIds'"), [_door]);
  });

  test('the featured path is read or written only where it is declared', () {
    final files = code();
    final hits = mentioning(files, "'/featured'");
    expect(hits.toSet(), {_door, ..._featuredReaders});
    // A guard that matches nothing passes for the wrong reason.
    expect(hits, contains(_door));
  });

  test('the feed data source stays a reader', () {
    final content = code()[_featuredReaders.first]!;
    for (final verb in ['putJson', 'postJson', 'patchJson', 'deleteJson']) {
      expect(content.contains(verb), isFalse, reason: '$verb in a reader');
    }
  });

  test('the shelf screen does not route through the feed', () {
    final content = code()[_shelfScreen]!;
    expect(content.contains('BlogFeedKind'), isFalse);
    expect(content.contains('FeaturedShelfRepository'), isTrue);
  });

  test('the door reads as much as it is allowed to write', () {
    final content = code()[_door]!;
    // Page size and capacity must be the same number, or a save sends back a
    // shorter shelf than the server has.
    expect(content.contains('kFeaturedShelfCapacity'), isTrue);
    expect(content.contains('limit'), isTrue);
  });
}
