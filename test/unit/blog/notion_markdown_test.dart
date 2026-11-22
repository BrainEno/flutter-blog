import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/features/blog/domain/notion_import/notion_zip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/zip_builder.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _canonical = '01234567-89ab-cdef-0123-456789abcdef';
const _englishId = 'fedcba9876543210fedcba9876543210';
const _englishCanonical = 'fedcba98-7654-3210-fedc-ba9876543210';

const _exported =
    '# 墙壁\n'
    '\n'
    'Date: October 8, 2026\n'
    'Published: Yes\n'
    'Slug: qiangbi\n'
    'Tags: 诗歌, 小说\n'
    'Rank: 1\n'
    'Mood: calm\n'
    '\n'
    'First **bold** and *italic* and [a link](https://example.com) and '
    '[another page](Other%20Page%20$_id.md).\n'
    '\n'
    '## Part two\n'
    '\n'
    '#### Deep heading\n'
    '\n'
    '- one\n'
    '- two\n'
    '\n'
    '1. first\n'
    '2. second\n'
    '\n'
    '```dart\n'
    'void main() {}\n'
    '```\n'
    '\n'
    '> quoted words\n'
    '\n'
    '---\n'
    '\n'
    '![Cover](https://prod-files-secure.s3.us-west-2.amazonaws.com/a.png?X-Amz-Signature=1)\n'
    '\n'
    '![Elsewhere](https://images.example.com/b.png)\n'
    '\n'
    '![Signed](https://bucket.example.com/c.png?X-Amz-Signature=2)\n'
    '\n'
    '![Local](%E5%A2%99%E5%A3%81/image.png)\n';

Map<String, dynamic> _page(NotionMarkdownBundle result) =>
    (result.bundle.json['pages'] as List).first as Map<String, dynamic>;

List<NotionMarkdownWarningKind> _kinds(NotionMarkdownBundle result) =>
    result.warnings.map((warning) => warning.kind).toList();

String _text(Map<String, dynamic> block) {
  final data = block[block['type']] as Map;
  return (data['rich_text'] as List)
      .map((run) => (run as Map)['plain_text'])
      .join();
}

void main() {
  group('markdownEntriesToBundle', () {
    test('reads a Notion export page: identity, properties and blocks', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry('Export/墙壁 $_id.md', _exported),
      ]);
      final page = _page(result);
      expect(page['id'], _canonical);
      expect(page.containsKey('source'), isFalse);

      final properties = page['properties'] as Map;
      expect(properties['Name']['title'][0]['plain_text'], '墙壁');
      expect(properties['Date']['date']['start'], '2026-10-08T00:00:00.000Z');
      expect(properties['Published']['checkbox'], isTrue);
      expect(properties['Slug']['rich_text'][0]['plain_text'], 'qiangbi');
      expect(
        (properties['Tags']['multi_select'] as List).map((t) => t['name']),
        ['诗歌', '小说'],
      );
      expect(properties.containsKey('Rank'), isFalse);
      expect(properties.containsKey('Mood'), isFalse);
      expect(result.bundle.pageTitle(0), '墙壁');

      final blocks = (page['blocks'] as List).cast<Map<String, dynamic>>();
      expect(blocks.map((block) => block['type']).toList(), [
        'paragraph',
        'heading_2',
        'heading_3',
        'bulleted_list_item',
        'bulleted_list_item',
        'numbered_list_item',
        'numbered_list_item',
        'code',
        'quote',
        'divider',
        'image',
        'image',
      ]);
      final runs = (blocks.first['paragraph']['rich_text'] as List)
          .cast<Map<String, dynamic>>();
      expect(runs.firstWhere((r) => r['plain_text'] == 'bold')['annotations'], {
        'bold': true,
      });
      expect(
        runs.firstWhere((r) => r['plain_text'] == 'italic')['annotations'],
        {'italic': true},
      );
      expect(
        runs.firstWhere((r) => r['plain_text'] == 'a link')['href'],
        'https://example.com',
      );
      final relative = runs.firstWhere(
        (r) => r['plain_text'] == 'another page',
      );
      expect(relative.containsKey('href'), isFalse);
      expect(_text(blocks[1]), 'Part two');
      expect(_text(blocks[2]), 'Deep heading');
      expect(_text(blocks[3]), 'one');
      expect(_text(blocks[7]), 'void main() {}');
      expect(blocks[7]['code']['language'], 'dart');
      expect(_text(blocks[8]), 'quoted words');
      expect(blocks[10]['image']['type'], 'file');
      expect(blocks[10]['image']['caption'][0]['plain_text'], 'Cover');
      expect(blocks[11]['image']['type'], 'external');
      expect(
        blocks[11]['image']['external']['url'],
        'https://images.example.com/b.png',
      );

      expect(
        _kinds(result),
        containsAll([
          NotionMarkdownWarningKind.propertyIgnored,
          NotionMarkdownWarningKind.relativeLinkDropped,
          NotionMarkdownWarningKind.headingLowered,
          NotionMarkdownWarningKind.signedImageDropped,
          NotionMarkdownWarningKind.localImageDropped,
        ]),
      );
      expect(
        _kinds(result),
        isNot(contains(NotionMarkdownWarningKind.fileNameIdentity)),
      );
      expect(
        result.warnings
            .firstWhere(
              (w) => w.kind == NotionMarkdownWarningKind.propertyIgnored,
            )
            .detail,
        'Mood',
      );
      expect(
        result.warnings
            .firstWhere(
              (w) => w.kind == NotionMarkdownWarningKind.localImageDropped,
            )
            .detail,
        'Local',
      );
    });

    test('a file without a page ID is known by its name, as on the web', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry('墙壁.md', '# 墙壁\n\nBody'),
      ]);
      // encodeURIComponent('墙壁.md') in the desk.
      expect(_page(result)['id'], 'markdown-file:%E5%A2%99%E5%A3%81.md');
      expect(_kinds(result), [NotionMarkdownWarningKind.fileNameIdentity]);
    });

    test('ordinary prose under the title is never taken for a property', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry('a.md', '# A\n\nNote: this is prose.\n'),
      ]);
      final page = _page(result);
      expect((page['properties'] as Map).keys, ['Name']);
      expect(
        _text((page['blocks'] as List).first as Map<String, dynamic>),
        'Note: this is prose.',
      );
    });

    test('unreadable properties fall back and say so', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry(
          'a $_id.md',
          '# A\n\nPublished: maybe\nDate: someday\n\nBody',
        ),
      ]);
      final properties = _page(result)['properties'] as Map;
      expect(properties.containsKey('Published'), isFalse);
      expect(properties.containsKey('Date'), isFalse);
      expect(_kinds(result), [
        NotionMarkdownWarningKind.publishedUnrecognized,
        NotionMarkdownWarningKind.dateUnrecognized,
      ]);
    });

    test('dates: a zoned instant is converted, a bare one read as UTC', () {
      String? start(String date) {
        final result = markdownEntriesToBundle([
          NotionMarkdownEntry('a $_id.md', '# A\n\nDate: $date\n\nBody'),
        ]);
        return (_page(result)['properties'] as Map)['Date']?['date']['start']
            as String?;
      }

      expect(start('2026-10-08T09:30:00+08:00'), '2026-10-08T01:30:00.000Z');
      expect(start('2026-10-08T09:30:00'), '2026-10-08T09:30:00.000Z');
      expect(start('2026-10-08'), '2026-10-08T00:00:00.000Z');
      expect(start('Oct 8, 2026 9:30 AM'), '2026-10-08T00:00:00.000Z');
      expect(start('February 30, 2026'), isNull);
    });

    test('English links pair pages chosen together, and warn otherwise', () {
      final primary = NotionMarkdownEntry(
        'Wall $_id.md',
        '# Wall\n\nEnglish: Wall%20EN%20$_englishId.md\n\nBody',
      );
      final english = NotionMarkdownEntry(
        'Wall EN $_englishId.md',
        '# Wall\n\nBody',
      );
      final paired = markdownEntriesToBundle([primary, english]);
      expect((_page(paired)['properties'] as Map)['English']['relation'], [
        {'id': _englishCanonical},
      ]);
      expect(paired.warnings, isEmpty);

      final alone = markdownEntriesToBundle([primary]);
      expect(_kinds(alone), [NotionMarkdownWarningKind.relationMissing]);
      expect(alone.warnings.single.detail, 'English');
    });

    test('tables, nested lists and HTML are kept as text and reported', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry(
          'a $_id.md',
          '# A\n\n'
              '| Name | Value |\n| --- | --- |\n| x | 1 |\n\n'
              '- outer\n  - inner\n\n'
              '<aside>\nA callout\n</aside>\n',
        ),
      ]);
      final texts = (_page(result)['blocks'] as List)
          .cast<Map<String, dynamic>>()
          .map(_text)
          .toList();
      expect(texts, containsAll(['Name | Value', 'x | 1']));
      expect(texts.any((text) => text.contains('inner')), isTrue);
      expect(texts.any((text) => text.contains('A callout')), isTrue);
      expect(
        _kinds(result),
        containsAll([
          NotionMarkdownWarningKind.tableFlattened,
          NotionMarkdownWarningKind.listSimplified,
          NotionMarkdownWarningKind.otherFlattened,
        ]),
      );
    });

    test('a page without a title is skipped; none at all is refused', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry('notes.md', 'no heading here'),
        const NotionMarkdownEntry('a.md', '# A\n\nBody'),
      ]);
      expect(result.bundle.pageCount, 1);
      expect(_kinds(result), contains(NotionMarkdownWarningKind.missingTitle));

      expect(
        () => markdownEntriesToBundle([
          const NotionMarkdownEntry('notes.md', 'no heading here'),
        ]),
        throwsA(
          isA<NotionImportSourceException>().having(
            (e) => e.error,
            'error',
            NotionImportSourceError.noPages,
          ),
        ),
      );
    });

    test('the same page chosen twice is refused', () {
      expect(
        () => markdownEntriesToBundle([
          const NotionMarkdownEntry('a/x $_id.md', '# A\n\nBody'),
          const NotionMarkdownEntry('b/x $_id.md', '# A\n\nBody'),
        ]),
        throwsA(
          isA<NotionImportSourceException>().having(
            (e) => e.error,
            'error',
            NotionImportSourceError.duplicatePage,
          ),
        ),
      );
    });
  });

  group('readPastedNotionText', () {
    test('pasted Markdown is one page known by its title', () {
      final source = readPastedNotionText('\n\n# 飞行器 / 草稿\n\nBody text\n');
      expect(source.bundle.pageCount, 1);
      expect(source.bundle.pageTitle(0), '飞行器 / 草稿');
      final id = (source.bundle.json['pages'] as List).single['id'] as String;
      expect(id, 'markdown-file:${Uri.encodeComponent('飞行器 - 草稿.md')}');
      expect(
        source.warnings.single.kind,
        NotionMarkdownWarningKind.pastedIdentity,
      );
    });

    test('pasted JSON is a bundle as it is', () {
      final source = readPastedNotionText(
        '\uFEFF {"version":1,"pages":[{"id":"p","properties":{},"blocks":[]}]}',
      );
      expect(source.bundle.pageCount, 1);
      expect(source.warnings, isEmpty);
      expect(
        () => readPastedNotionText('{"version":2}'),
        throwsA(
          isA<NotionImportSourceException>().having(
            (e) => e.error,
            'error',
            NotionImportSourceError.invalidBundle,
          ),
        ),
      );
    });
  });

  group('readNotionImportFiles', () {
    NotionImportFile file(String name, String text) =>
        NotionImportFile(name: name, bytes: utf8.encode(text));

    test('a single JSON file is a bundle', () {
      final source = readNotionImportFiles([
        file('b.json', '{"version":1,"pages":[]}'),
      ]);
      expect(source.bundle.pageCount, 0);
      expect(source.markdownFiles, 0);
    });

    test('Markdown files and ZIPs are converted together', () {
      final zip = buildZip([
        ZipEntry.text('Export/One $_id.md', '# One\n\nBody'),
        const ZipEntry('Export/One/image.png', [1, 2, 3]),
      ]);
      final source = readNotionImportFiles([
        file('Two.md', '# Two\n\nBody'),
        NotionImportFile(name: 'export.ZIP', bytes: zip),
      ]);
      expect(source.bundle.pageCount, 2);
      expect(source.markdownFiles, 2);
      expect(source.bundle.pageTitle(0), 'Two');
      expect(source.bundle.pageTitle(1), 'One');
    });

    test('other files, mixed JSON and bad text are refused by name', () {
      Matcher refused(NotionImportSourceError error, String name) => throwsA(
        isA<NotionImportSourceException>()
            .having((e) => e.error, 'error', error)
            .having((e) => e.name, 'name', name),
      );

      expect(
        () => readNotionImportFiles([file('notes.txt', 'x')]),
        refused(NotionImportSourceError.unsupportedFile, 'notes.txt'),
      );
      expect(
        () => readNotionImportFiles([
          file('a.md', '# A\n\nBody'),
          file('b.json', '{}'),
        ]),
        refused(NotionImportSourceError.unsupportedFile, 'b.json'),
      );
      expect(
        () => readNotionImportFiles([
          NotionImportFile(name: 'bad.md', bytes: Uint8List.fromList([0xff])),
        ]),
        refused(NotionImportSourceError.invalidText, 'bad.md'),
      );
      expect(
        () => readNotionImportFiles([file('b.json', '[]')]),
        refused(NotionImportSourceError.invalidBundle, 'b.json'),
      );
    });

    test('more than the request limit is refused before reading', () {
      expect(
        () => readNotionImportFiles([
          NotionImportFile(name: 'a.md', bytes: Uint8List(9 * 1024 * 1024)),
        ]),
        throwsA(
          isA<NotionImportSourceException>().having(
            (e) => e.error,
            'error',
            NotionImportSourceError.tooLarge,
          ),
        ),
      );
    });
  });

  group('readNotionZip', () {
    Matcher refused(NotionImportSourceError error) => throwsA(
      isA<NotionImportSourceException>().having((e) => e.error, 'error', error),
    );

    test('reads Markdown, stored or deflated, and skips everything else', () {
      final entries = readNotionZip(
        buildZip([
          ZipEntry.text('a.md', '# A', deflate: false),
          ZipEntry.text('folder/b.MD', '# B'),
          ZipEntry.text('__MACOSX/folder/._b.md', 'junk'),
          const ZipEntry('folder/', []),
          const ZipEntry('folder/c.png', [9, 9]),
        ], comment: 'exported'),
      );
      expect(entries.map((e) => e.name), ['a.md', 'folder/b.MD']);
      expect(entries.map((e) => e.text), ['# A', '# B']);
    });

    test('opens the part archives Notion nests inside a large export', () {
      final part = buildZip([ZipEntry.text('Part/p.md', '# P')]);
      final entries = readNotionZip(
        buildZip([ZipEntry('Export-Part-1.zip', part)]),
      );
      expect(entries.single.text, '# P');
      // But not a ZIP inside a part archive.
      final deeper = buildZip([
        ZipEntry('outer.zip', buildZip([ZipEntry('inner.zip', part)])),
      ]);
      expect(readNotionZip(deeper), isEmpty);
    });

    test('a cut-short, encrypted or lying archive is refused', () {
      final whole = buildZip([ZipEntry.text('a.md', '# A')]);
      expect(
        () => readNotionZip(Uint8List.sublistView(whole, 0, whole.length - 3)),
        refused(NotionImportSourceError.invalidZip),
      );
      expect(
        () => readNotionZip(Uint8List.fromList(utf8.encode('not a zip'))),
        refused(NotionImportSourceError.invalidZip),
      );
      expect(
        () => readNotionZip(
          buildZip([ZipEntry('a.md', utf8.encode('# A'), encrypted: true)]),
        ),
        refused(NotionImportSourceError.invalidZip),
      );
      expect(
        () => readNotionZip(
          buildZip([
            ZipEntry('a.md', utf8.encode('# A body'), declaredSize: 3),
          ]),
        ),
        refused(NotionImportSourceError.invalidZip),
      );
    });

    test('inflating stops at the limit, whatever the header claims', () {
      final bomb = buildZip([
        ZipEntry('a.md', Uint8List(9 * 1024 * 1024), declaredSize: 10),
      ]);
      expect(bomb.length, lessThan(64 * 1024));
      expect(
        () => readNotionZip(bomb),
        refused(NotionImportSourceError.tooLarge),
      );
    });

    test('too many entries or pages are refused', () {
      expect(
        () => readNotionZip(
          buildZip([
            for (var i = 0; i < 2001; i++)
              ZipEntry('f$i.png', const [0], deflate: false),
          ]),
        ),
        refused(NotionImportSourceError.tooManyEntries),
      );
      expect(
        () => readNotionZip(
          buildZip([
            for (var i = 0; i < 201; i++)
              ZipEntry.text('p$i.md', '# P$i', deflate: false),
          ]),
        ),
        refused(NotionImportSourceError.tooManyPages),
      );
    });

    test('Markdown that is not UTF-8 is refused', () {
      expect(
        () => readNotionZip(
          buildZip([
            ZipEntry('a.md', const [0xc3, 0x28], deflate: false),
          ]),
        ),
        refused(NotionImportSourceError.invalidText),
      );
    });
  });
}
