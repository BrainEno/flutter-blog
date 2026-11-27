// One door for the taxonomy writes, one read path for the catalogue (#381).
//
// `POST /taxonomies` accepts a body of exactly `{kind, slug, name, description,
// locale}` and answers any other key with `400 The request contains unsupported
// fields.`; `DELETE /taxonomies/:id` needs the UUID the catalogue carried. Two
// mistakes are cheap to make here and expensive on a public catalogue, so both
// are machine-checked rather than reviewed:
//
// - A second writer would be a second copy of that body. The failure reads like
//   the editor's fault, not like the client's.
// - A screen that read `/categories` for itself would page it differently from
//   the reader path, and a screen that spliced its own new row into the list
//   would show a name the server may not have accepted - and an id nobody has.
//
// Each rule below is a scan over code lines only: a doc comment that names
// `POST /taxonomies` explains the contract, it does not issue one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_files.dart';

/// The only file allowed to send a taxonomy body.
const _door =
    'lib/features/blog/data/repositories/taxonomy_admin_repository_impl.dart';

/// The screen that maintains the catalogue.
const _screen = 'lib/features/blog/presentation/pages/taxonomy_admin_page.dart';

/// The one reader of `/categories`, shared with everyone browsing.
const _reader =
    'lib/features/blog/data/datasources/category_remote_data_source.dart';

void main() {
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

  test('the taxonomy body is built in exactly one place', () {
    final files = code();
    // `'kind': 'category'` is the whole shape of the request body: whoever
    // writes it also has to honour the key whitelist.
    expect(mentioning(files, "'kind': 'category'"), [_door]);
  });

  test('only the door speaks to /taxonomies, and it never reads there', () {
    final files = code();
    final hits = mentioning(files, "'/taxonomies'");
    expect(hits.toSet(), {_door});
    // A guard that matches nothing passes for the wrong reason.
    expect(hits, contains(_door));
    expect(mentioning(files, "'/categories'"), [_reader]);
  });

  test('both writes are one-shot and fenced', () {
    final content = code()[_door]!;
    // A create must never be replayed after a 401: it would duplicate a
    // category that may have landed already.
    expect(content.contains('postJsonForViewerOnce'), isTrue);
    expect(content.contains('sessionFence:'), isTrue);
    for (final verb in [
      'client.postJson(',
      'client.putJson(',
      'client.patchJson(',
    ]) {
      expect(content.contains(verb), isFalse, reason: '$verb retries a write');
    }
  });

  test('the screen reaches the catalogue only through the door', () {
    final content = code()[_screen]!;
    expect(content.contains('TaxonomyAdminRepository'), isTrue);
    // The page has no transport of its own: not the reader's data source, not a
    // client, not a path.
    expect(content.contains('CategoryRemoteDataSource'), isFalse);
    expect(content.contains('getJson'), isFalse);
    expect(content.contains('http.Client'), isFalse);
  });

  test('every write is followed by a re-read, and no row is invented', () {
    final content = code()[_screen]!;
    // Both writes end by asking the server again: the catalogue is shared with
    // other editors, so what is on screen is only worth trusting after an
    // answer. A floor rather than an exact count, because a screen may grow a
    // third reason to re-read without that being a regression.
    final reReads = content.split('await _reload();').length - 1;
    expect(reReads, greaterThanOrEqualTo(2));
    // A locally spliced row would carry a name the server may not have taken
    // and an id nobody has - which is a row that cannot be removed again.
    expect(content.contains('_entries = [..._entries'), isFalse);
  });

  test('a row without an id is offered no delete', () {
    final content = code()[_screen]!;
    expect(content.contains('row.id.isNotEmpty'), isTrue);
    expect(content.contains('taxonomyAdminNoId'), isTrue);
  });

  test('every catalogue key the app uses exists in both languages', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final zh =
        jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
            as Map<String, dynamic>;
    // Only the localisation accesses count: `RoutePaths.taxonomyAdmin` is a
    // route, and demanding a string for it would be nonsense.
    final used = <String>{};
    final accesses = RegExp(r'l10n\.(taxonomyAdmin[A-Za-z0-9_]*)');
    for (final content in code().values) {
      for (final match in accesses.allMatches(content)) {
        used.add(match.group(1)!);
      }
    }
    expect(used, isNotEmpty, reason: 'the scan must reach the screen');
    for (final key in used) {
      expect(en[key], isA<String>(), reason: '$key missing from app_en.arb');
      expect(zh[key], isA<String>(), reason: '$key missing from app_zh.arb');
    }
    // A key nobody uses is a dead string that still ships: the catalogues are
    // the screen's, not a museum.
    final declared = en.keys
        .where((key) => key.startsWith('taxonomyAdmin'))
        .toSet();
    expect(declared.difference(used), isEmpty);
  });
}
