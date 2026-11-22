import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/features/blog/domain/notion_import/notion_csv.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/features/blog/domain/notion_import/notion_zip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/zip_builder.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _canonical = '01234567-89ab-cdef-0123-456789abcdef';
const _englishId = 'fedcba9876543210fedcba9876543210';
const _englishCanonical = 'fedcba98-7654-3210-fedc-ba9876543210';
const _pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

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
          NotionMarkdownWarningKind.localImageMissing,
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
              (w) => w.kind == NotionMarkdownWarningKind.localImageMissing,
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
      expect(start('2026/10/08'), '2026-10-08T00:00:00.000Z');
      expect(start('2026.10.8'), '2026-10-08T00:00:00.000Z');
      expect(start('2026\u5e7410\u67088\u65e5'), '2026-10-08T00:00:00.000Z');
      expect(start('Sept 1 2026'), '2026-09-01T00:00:00.000Z');
      expect(start('September 1 2026'), '2026-09-01T00:00:00.000Z');
      expect(start('2026-10-08T09:30:00.123456Z'), '2026-10-08T09:30:00.123Z');
      // As on the web: a time after the day, an ambiguous order or a
      // misspelt month is not a date.
      expect(start('Oct 8, 2026 9:30 AM'), isNull);
      expect(start('10/08/2026'), isNull);
      expect(start('Octx 8, 2026'), isNull);
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

    test('without a # title the file name is the title, and says so', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry(
          'Export/Wall $_id.md',
          'Date: 2026-10-08\n\nFirst line.',
        ),
      ]);
      expect(result.bundle.pageTitle(0), 'Wall');
      final page = _page(result);
      expect(
        (page['properties'] as Map)['Date']['date']['start'],
        '2026-10-08T00:00:00.000Z',
      );
      expect(
        _text((page['blocks'] as List).single as Map<String, dynamic>),
        'First line.',
      );
      expect(
        result.warnings.single.kind,
        NotionMarkdownWarningKind.titleFromFileName,
      );
      expect(result.warnings.single.detail, 'Wall');
    });

    test('a page with neither title nor name is skipped; none is refused', () {
      final result = markdownEntriesToBundle([
        const NotionMarkdownEntry('.md', 'no heading here'),
        const NotionMarkdownEntry('a.md', '# A\n\nBody'),
      ]);
      expect(result.bundle.pageCount, 1);
      expect(_kinds(result), contains(NotionMarkdownWarningKind.missingTitle));

      expect(
        () => markdownEntriesToBundle([
          const NotionMarkdownEntry('.md', 'no heading here'),
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

    test('too much text, or too much in all, is refused before reading', () {
      final refusedTooLarge = throwsA(
        isA<NotionImportSourceException>().having(
          (e) => e.error,
          'error',
          NotionImportSourceError.tooLarge,
        ),
      );
      // Markdown and CSV share the request's budget...
      expect(
        () => readNotionImportFiles([
          NotionImportFile(name: 'a.md', bytes: Uint8List(5 * 1024 * 1024)),
          NotionImportFile(name: 'a.csv', bytes: Uint8List(4 * 1024 * 1024)),
        ]),
        refusedTooLarge,
      );
      // ...and images may make the whole larger, up to a point.
      expect(
        () => readNotionImportFiles([
          file('a.md', '# A'),
          NotionImportFile(name: 'p.png', bytes: Uint8List(65 * 1024 * 1024)),
        ]),
        refusedTooLarge,
      );
      final source = readNotionImportFiles([
        file('a.md', '# A\n\nBody'),
        NotionImportFile(name: 'p.png', bytes: Uint8List(9 * 1024 * 1024)),
      ]);
      expect(source.bundle.pageCount, 1);
      // An unused image is not carried.
      expect(source.images, isEmpty);
      expect(source.markdownFiles, 1);
    });
  });

  group('readNotionZip', () {
    Matcher refused(NotionImportSourceError error) => throwsA(
      isA<NotionImportSourceException>().having((e) => e.error, 'error', error),
    );

    test('reads Markdown and CSV, stored or deflated, and skips the rest', () {
      final contents = readNotionZip(
        buildZip([
          ZipEntry.text('a.md', '# A', deflate: false),
          ZipEntry.text('folder/b.MD', '# B'),
          ZipEntry.text('db_all.csv', 'Name,Tags'),
          ZipEntry.text('__MACOSX/folder/._b.md', 'junk'),
          const ZipEntry('folder/', []),
          const ZipEntry('folder/c.png', [9, 9]),
          const ZipEntry('folder/notes.pdf', [1]),
        ], comment: 'exported'),
      );
      final entries = contents.entries;
      expect(entries.map((e) => e.name), ['a.md', 'folder/b.MD', 'db_all.csv']);
      expect(entries.map((e) => e.text), ['# A', '# B', 'Name,Tags']);
      expect(contents.images.keys, ['folder/c.png']);
      expect(contents.images['folder/c.png']!.size, 2);
      expect(contents.images['folder/c.png']!.read(), [9, 9]);
    });

    test('an image is inflated only when read, and checked then', () {
      final png = [..._pngSignature, ...List.filled(5000, 7)];
      final contents = readNotionZip(
        buildZip([
          ZipEntry('a/ok.png', png),
          ZipEntry('a/lying.png', png, declaredSize: 10),
          ZipEntry(
            'a/huge.png',
            Uint8List(9 * 1024 * 1024),
            declaredSize: 9 * 1024 * 1024,
          ),
        ]),
      );
      expect(contents.images['a/ok.png']!.read(), png);
      expect(
        () => contents.images['a/lying.png']!.read(),
        refused(NotionImportSourceError.invalidZip),
      );
      expect(
        () => contents.images['a/huge.png']!.read(),
        refused(NotionImportSourceError.tooLarge),
      );
    });

    test('opens the part archives Notion nests inside a large export', () {
      final part = buildZip([ZipEntry.text('Part/p.md', '# P')]);
      final entries = readNotionZip(
        buildZip([ZipEntry('Export-Part-1.zip', part)]),
      ).entries;
      expect(entries.single.text, '# P');
      // But not a ZIP inside a part archive.
      final deeper = buildZip([
        ZipEntry('outer.zip', buildZip([ZipEntry('inner.zip', part)])),
      ]);
      expect(readNotionZip(deeper).entries, isEmpty);
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

  group('database CSV', () {
    test('parses quoted cells, doubled quotes, line breaks and a BOM', () {
      expect(
        parseNotionCsv(
          '\uFEFFName,Tags\r\n"A, b","say ""hi""\nthere"\r\n\r\nC,\n',
        ),
        [
          ['Name', 'Tags'],
          ['A, b', 'say "hi"\nthere'],
          ['C', ''],
        ],
      );
    });

    test('the _all table wins over the view of the same database', () {
      final tables = notionTablesOf(const [
        NotionMarkdownEntry('Export/Works.csv', 'Name,Tags'),
        NotionMarkdownEntry('Export/Works_all.csv', 'Name,Tags,Date'),
        NotionMarkdownEntry('Export/Other.csv', 'Name'),
        NotionMarkdownEntry('Export/page.md', '# P'),
      ]);
      expect(tables.map((t) => t.name), ['Works.csv', 'Other.csv']);
      expect(tables.first.header, ['Name', 'Tags', 'Date']);
    });

    const csv =
        'Name,\u65e5\u671f,\u6807\u7b7e,Published,Slug,\u6458\u8981,Mood,Rank,Cover\n'
        'Wall,2026\u5e7410\u67088\u65e5,"\u8bd7\u6b4c\uff0c\u5c0f\u8bf4\u3001\u968f\u7b14",Yes,wall,Short,calm,1,https://img.example/a.png\n'
        'Twin,2026-01-01,,No,,,,,\n'
        'Twin,2026-01-02,,No,,,,,\n'
        'Range,October 8 2026 \u2192 October 9 2026,,No,,,,,Range/cover.png\n';

    NotionMarkdownBundle convert(List<NotionMarkdownEntry> pages) =>
        markdownEntriesToBundle([
          ...pages,
          const NotionMarkdownEntry('Export/Works_all.csv', csv),
        ]);

    test('fills only the properties the Markdown left empty', () {
      final result = convert([
        const NotionMarkdownEntry(
          'Export/Wall $_id.md',
          '# Wall\n\nSlug: from-markdown\n\nBody',
        ),
      ]);
      final properties = _page(result)['properties'] as Map;
      expect(properties['Slug']['rich_text'][0]['plain_text'], 'from-markdown');
      expect(properties['Date']['date']['start'], '2026-10-08T00:00:00.000Z');
      expect(
        (properties['Tags']['multi_select'] as List).map((t) => t['name']),
        ['\u8bd7\u6b4c', '\u5c0f\u8bf4', '\u968f\u7b14'],
      );
      expect(properties['Published']['checkbox'], isTrue);
      expect(properties['Excerpt']['rich_text'][0]['plain_text'], 'Short');
      expect(
        properties['FeaturedImage']['files'][0]['external']['url'],
        'https://img.example/a.png',
      );
      final filled = result.warnings.singleWhere(
        (w) => w.kind == NotionMarkdownWarningKind.csvFilled,
      );
      expect(filled.table, 'Works.csv');
      expect(filled.detail, 'Date, Excerpt, FeaturedImage, Published, Tags');
      final ignored = result.warnings.singleWhere(
        (w) => w.kind == NotionMarkdownWarningKind.csvColumnsIgnored,
      );
      expect(ignored.detail, 'Mood');
      expect(ignored.table, 'Works.csv');
    });

    test('a row is found by file name when the title differs', () {
      final result = convert([
        const NotionMarkdownEntry('Export/Wall $_id.md', '# Renamed\n\nBody'),
      ]);
      final properties = _page(result)['properties'] as Map;
      expect(properties['Date']['date']['start'], '2026-10-08T00:00:00.000Z');
    });

    test('no row, two rows, a range and a local cover are each reported', () {
      final result = convert([
        const NotionMarkdownEntry('Export/Nobody.md', '# Nobody\n\nBody'),
        const NotionMarkdownEntry('Export/Twin.md', '# Twin\n\nBody'),
        const NotionMarkdownEntry('Export/Range.md', '# Range\n\nBody'),
      ]);
      final bySource = <String, List<NotionMarkdownWarningKind>>{};
      for (final warning in result.warnings) {
        bySource.putIfAbsent(warning.source, () => []).add(warning.kind);
      }
      expect(
        bySource['Export/Nobody.md'],
        contains(NotionMarkdownWarningKind.csvNoRow),
      );
      expect(
        bySource['Export/Twin.md'],
        contains(NotionMarkdownWarningKind.csvAmbiguousRow),
      );
      expect(
        bySource['Export/Range.md'],
        containsAll([
          NotionMarkdownWarningKind.dateRange,
          NotionMarkdownWarningKind.csvLocalCover,
          NotionMarkdownWarningKind.csvFilled,
        ]),
      );
      final range = (result.bundle.json['pages'] as List)[2] as Map;
      expect(
        range['properties']['Date']['date']['start'],
        '2026-10-08T00:00:00.000Z',
      );
      expect(range['properties']['Published']['checkbox'], isFalse);
    });

    test('a status column called Published never publishes', () {
      final result = markdownEntriesToBundle(const [
        NotionMarkdownEntry('Export/A.md', '# A\n\nBody'),
        NotionMarkdownEntry(
          'Export/Works.csv',
          'Name,Published\nA,Yes\nB,Draft\n',
        ),
      ]);
      final properties = _page(result)['properties'] as Map;
      expect(properties.containsKey('Published'), isFalse);
      expect(
        result.warnings
            .singleWhere(
              (w) =>
                  w.kind == NotionMarkdownWarningKind.csvPublishedNotCheckbox,
            )
            .detail,
        'Published',
      );
      expect(
        _kinds(result),
        contains(NotionMarkdownWarningKind.csvNothingToFill),
      );
    });

    test('CSV alone is not an import', () {
      expect(
        () => markdownEntriesToBundle(const [
          NotionMarkdownEntry('Works.csv', 'Name\nA\n'),
        ]),
        throwsA(
          isA<NotionImportSourceException>().having(
            (e) => e.error,
            'error',
            NotionImportSourceError.csvOnly,
          ),
        ),
      );
    });

    test('checkbox spellings', () {
      for (final yes in ['Yes', 'true', 'Y', '__YES__', '\u662f']) {
        expect(notionBoolean(yes), isTrue, reason: yes);
      }
      for (final no in ['No', 'FALSE', 'n', '__no__', '\u5426']) {
        expect(notionBoolean(no), isFalse, reason: no);
      }
      expect(notionBoolean('Draft'), isNull);
    });
  });

  group('local images', () {
    final png = Uint8List.fromList([..._pngSignature, 1, 2, 3]);

    test('an export image becomes a stand-in the app uploads later', () {
      final zip = buildZip([
        ZipEntry.text(
          'Export/Wall $_id.md',
          '# Wall\n\n'
              '![A wall](Wall%20$_id/photo.png)\n\n'
              '![Moving](Wall%20$_id/anim.gif)\n\n'
              '![Gone](Wall%20$_id/missing.png)\n\n'
              '![Big](Wall%20$_id/big.jpg)\n',
        ),
        ZipEntry('Export/Wall $_id/photo.png', png),
        ZipEntry('Export/Wall $_id/anim.gif', png),
        ZipEntry(
          'Export/Wall $_id/big.jpg',
          png,
          declaredSize: 9 * 1024 * 1024,
        ),
      ]);
      final source = readNotionImportFiles([
        NotionImportFile(name: 'export.zip', bytes: zip),
      ]);
      const key = 'Export/Wall $_id/photo.png';
      expect(source.images.keys, [key]);
      expect(source.images[key]!.read(), png);
      final blocks =
          ((source.bundle.json['pages'] as List).single as Map)['blocks']
              as List;
      expect(blocks, hasLength(1));
      expect(notionLocalImageKey(blocks.single), key);
      expect(blocks.single['image']['caption'][0]['plain_text'], 'A wall');
      expect(notionLocalImageKeys(source.bundle), [key]);
      final details = {for (final w in source.warnings) w.kind: w.detail};
      expect(
        details[NotionMarkdownWarningKind.localImageUnsupported],
        'anim.gif',
      );
      expect(details[NotionMarkdownWarningKind.localImageMissing], 'Gone');
      expect(details[NotionMarkdownWarningKind.localImageTooLarge], 'big.jpg');
    });

    test('images chosen beside the pages are found by file name', () {
      final source = readNotionImportFiles([
        NotionImportFile(
          name: 'Wall.md',
          bytes: utf8.encode('# Wall\n\n![x](Wall%20abc/photo.png)\n'),
        ),
        NotionImportFile(name: 'photo.png', bytes: png),
      ]);
      expect(source.images.keys, ['photo.png']);
      expect(source.images['photo.png']!.read(), png);
    });

    test('resolving a reference: relative, encoded, and by unique name', () {
      NotionLocalImage image(String name) =>
          NotionLocalImage(name: name, size: 1, read: () => png);
      final images = {
        for (final name in ['A/b/c.png', 'A/d.png', 'X/d.png', 'solo.png'])
          name: image(name),
      };
      String? resolve(String page, String src) =>
          resolveNotionLocalImage(images, page, src)?.name;
      expect(resolve('A/page.md', 'b/c.png'), 'A/b/c.png');
      expect(resolve('A/b/page.md', '../d.png'), 'A/d.png');
      expect(resolve('A/page.md', './b/c.png?x=1'), 'A/b/c.png');
      expect(resolve('page.md', 'folder/solo.png'), 'solo.png');
      // Two images share the name: neither is guessed.
      expect(resolve('page.md', 'folder/d.png'), isNull);
      expect(resolve('page.md', '%zz.png'), isNull);
    });

    test('content types come from the bytes, not the name', () {
      expect(notionUploadableImageType(png), 'image/png');
      expect(
        notionUploadableImageType(Uint8List.fromList([0xff, 0xd8, 0xff, 0])),
        'image/jpeg',
      );
      expect(
        notionUploadableImageType(
          Uint8List.fromList([
            ...ascii.encode('RIFF'),
            0,
            0,
            0,
            0,
            ...ascii.encode('WEBP'),
          ]),
        ),
        'image/webp',
      );
      expect(
        notionUploadableImageType(Uint8List.fromList(ascii.encode('GIF89a'))),
        isNull,
      );
      expect(notionUploadableImageType(Uint8List(0)), isNull);
    });

    test('uploaded addresses replace stand-ins; refused images go', () {
      final bundle = NotionBundle.parse(
        jsonEncode({
          'version': 1,
          'extra': 'kept',
          'pages': [
            {
              'id': 'p',
              'properties': <String, dynamic>{},
              'blocks': [
                {
                  'type': 'image',
                  'image': {
                    'type': 'external',
                    'external': {'url': notionLocalImageUrl('a/1.png')},
                    'caption': [
                      {'plain_text': 'one'},
                    ],
                  },
                },
                {
                  'type': 'image',
                  'image': {
                    'type': 'external',
                    'external': {'url': notionLocalImageUrl('a/2.png')},
                  },
                },
                {
                  'type': 'image',
                  'image': {
                    'type': 'external',
                    'external': {'url': 'https://example.com/x.png'},
                  },
                },
              ],
            },
          ],
        }),
      );
      expect(notionLocalImageKeys(bundle), ['a/1.png', 'a/2.png']);
      final ready = withNotionLocalImages(bundle, {
        'a/1.png': 'https://site.example/api/v1/media/1',
      });
      expect(ready.json['extra'], 'kept');
      final blocks =
          ((ready.json['pages'] as List).single as Map)['blocks'] as List;
      expect(blocks, hasLength(2));
      expect(
        blocks.first['image']['external']['url'],
        'https://site.example/api/v1/media/1',
      );
      expect(blocks.first['image']['caption'][0]['plain_text'], 'one');
      expect(
        blocks.last['image']['external']['url'],
        'https://example.com/x.png',
      );
      expect(notionLocalImageKeys(ready), isEmpty);
      expect(notionLocalImageKey({'type': 'paragraph'}), isNull);
    });
  });
}
