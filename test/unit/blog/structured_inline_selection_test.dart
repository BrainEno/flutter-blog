import 'dart:convert';
import 'dart:math';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_inline_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

StructuredArticleDraft fixture() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredArticleDraft document(
  List<Map<String, Object?>> blocks, {
  int version = 1,
}) => StructuredArticleDraft.parse(version: version, blocks: blocks);

Map<String, Object?> paragraph(String text, {List<Object?>? runs}) => {
  'id': 'p',
  'type': 'paragraph',
  'text': text,
  if (runs != null) 'inlines': runs,
};

Map<String, Object?> listBlock({bool formatted = true}) => {
  'id': 'l',
  'type': 'list',
  'ordered': true,
  'items': ['alpha', 'beta', 'gamma'],
  if (formatted)
    'itemInlines': [
      [
        {
          'text': 'al',
          'marks': ['bold'],
          'href': '/a',
        },
        {'text': 'pha', 'marks': <String>[]},
      ],
      [
        {'text': 'be', 'href': '/b'},
        {
          'text': 'ta',
          'marks': ['italic'],
        },
      ],
      [
        {'text': 'gamma'},
      ],
    ],
};

StructuredInlineSelection select(
  StructuredArticleDraft value,
  int start,
  int end, {
  String id = 'p',
}) => StructuredInlineSelection.textBlock(
  document: value,
  blockId: id,
  start: start,
  end: end,
);

StructuredInlineSelection selectItem(
  StructuredArticleDraft value,
  int item,
  int start,
  int end, {
  String id = 'l',
}) => StructuredInlineSelection.listItem(
  document: value,
  blockId: id,
  itemIndex: item,
  start: start,
  end: end,
);

List<dynamic> textRuns(StructuredArticleDraft value, {String id = 'p'}) =>
    value.blocks.firstWhere((b) => b['id'] == id)['inlines'] as List;

List<dynamic> itemRuns(StructuredArticleDraft value, int index) =>
    (value.blocks.firstWhere((b) => b['id'] == 'l')['itemInlines']
            as List)[index]
        as List;

String textOfRuns(List runs) => runs.map((r) => r['text'] as String).join();

List<Set<String>> characterMarks(StructuredArticleDraft value) {
  final runs = textRuns(value);
  return [
    for (final run in runs)
      for (var i = 0; i < (run['text'] as String).length; i++)
        Set<String>.of((run['marks'] as List?)?.cast<String>() ?? []),
  ];
}

List<String?> characterLinks(StructuredArticleDraft value) {
  final runs = textRuns(value);
  return [
    for (final run in runs)
      for (var i = 0; i < (run['text'] as String).length; i++)
        run['href'] as String?,
  ];
}

void main() {
  group('capture and validation', () {
    test('records exact UTF-16 offsets and target text', () {
      final body = document([paragraph('A😀文')]);
      final range = select(body, 1, 3);
      expect(range.blockId, 'p');
      expect(range.itemIndex, isNull);
      expect(range.start, 1);
      expect(range.end, 3);
      expect(range.text, 'A😀文');
      expect(range.text.substring(range.start, range.end), '😀');
    });

    test('captures each supported text block without inferring Markdown', () {
      final body = fixture();
      for (final id in ['heading', 'paragraph', 'quote']) {
        final block = body.blocks.firstWhere((b) => b['id'] == id);
        final text = block['text'] as String;
        final range = select(body, 0, text.length, id: id);
        expect(range.text, text);
        expect(range.itemIndex, isNull);
      }
      expect(body.blocks[2]['text'], 'literal **asterisks**');
    });

    test('captures exact list item and preserves its item index', () {
      final body = document([listBlock()]);
      final range = selectItem(body, 1, 1, 3);
      expect(range.blockId, 'l');
      expect(range.itemIndex, 1);
      expect(range.text, 'beta');
      expect(range.text.substring(range.start, range.end), 'et');
    });

    test('rejects collapsed, reversed and out-of-bounds ranges', () {
      final body = document([paragraph('abcd'), listBlock()]);
      for (final pair in [
        [-1, 1],
        [0, 0],
        [2, 1],
        [0, 5],
        [4, 4],
        [100, 101],
      ]) {
        expect(() => select(body, pair[0], pair[1]), throwsRangeError);
        expect(() => selectItem(body, 1, pair[0], pair[1]), throwsRangeError);
      }
    });

    test('rejects either boundary through an emoji surrogate pair', () {
      final body = document([paragraph('A😀B')]);
      expect(() => select(body, 0, 2), throwsFormatException);
      expect(() => select(body, 2, 4), throwsFormatException);
      expect(() => select(body, 1, 2), throwsFormatException);
      expect(() => select(body, 2, 3), throwsFormatException);
      expect(select(body, 1, 3).text.substring(1, 3), '😀');
    });

    test('also rejects a surrogate pair spanning two existing runs', () {
      final emoji = '😀';
      final high = emoji.substring(0, 1);
      final low = emoji.substring(1);
      final body = document([
        paragraph(
          'A$high${low}B',
          runs: [
            {'text': 'A$high'},
            {
              'text': '${low}B',
              'marks': ['bold'],
            },
          ],
        ),
      ]);
      expect(() => select(body, 0, 2), throwsFormatException);
      expect(() => select(body, 2, 4), throwsFormatException);
      final result = select(body, 1, 3).setMark(body, 'italic', enabled: true);
      expect(textOfRuns(textRuns(result)), 'A😀B');
    });

    test('selection rejects absent IDs, wrong kinds and list bounds', () {
      final body = document([
        paragraph('abc'),
        listBlock(),
        {'id': 'img', 'type': 'image', 'src': '/image', 'alt': ''},
      ]);
      expect(() => select(body, 0, 1, id: 'missing'), throwsArgumentError);
      expect(() => select(body, 0, 1, id: 'img'), throwsArgumentError);
      expect(() => select(body, 0, 1, id: 'l'), throwsArgumentError);
      expect(() => selectItem(body, 0, 0, 1, id: 'p'), throwsArgumentError);
      expect(() => selectItem(body, -1, 0, 1), throwsRangeError);
      expect(() => selectItem(body, 3, 0, 1), throwsRangeError);
    });

    test('v0 refuses formatting instead of upgrading the version', () {
      final body = document([
        paragraph('plain'),
        listBlock(formatted: false),
      ], version: 0);
      expect(() => select(body, 0, 1), throwsStateError);
      expect(() => selectItem(body, 0, 0, 1), throwsStateError);
      expect(body.version, 0);
      expect(body.blocks.first.containsKey('inlines'), isFalse);
      expect(body.blocks.last.containsKey('itemInlines'), isFalse);
    });

    test(
      'combining sequences are explicit code-unit ranges, not graphemes',
      () {
        final body = document([paragraph('e\u0301!')]);
        final result = select(
          body,
          1,
          2,
        ).setMark(body, 'underline', enabled: true);
        expect(textOfRuns(textRuns(result)), 'e\u0301!');
        expect(textRuns(result), [
          {'text': 'e'},
          {
            'text': '\u0301',
            'marks': ['underline'],
          },
          {'text': '!'},
        ]);
      },
    );
  });

  group('formatting with exact run preservation', () {
    test('partial plain block promotes only the selected text', () {
      final body = document([paragraph('abcdef')]);
      final result = select(body, 2, 4).setMark(body, 'bold', enabled: true);
      expect(result.blocks.single['text'], 'abcdef');
      expect(textRuns(result), [
        {'text': 'ab'},
        {
          'text': 'cd',
          'marks': ['bold'],
        },
        {'text': 'ef'},
      ]);
      expect(body.blocks.single.containsKey('inlines'), isFalse);
    });

    test('a whole plain block becomes exactly one explicit run', () {
      final body = document([paragraph('abc')]);
      final result = select(body, 0, 3).setMark(body, 'code', enabled: true);
      expect(textRuns(result), [
        {
          'text': 'abc',
          'marks': ['code'],
        },
      ]);
      expect(result.version, 1);
    });

    test(
      'splits within a linked run without losing the link or mark order',
      () {
        final body = document([
          paragraph(
            'abcdef',
            runs: [
              {
                'text': 'abcdef',
                'marks': ['italic', 'code'],
                'href': '/guide',
              },
            ],
          ),
        ]);
        final result = select(body, 1, 5).setMark(body, 'bold', enabled: true);
        expect(textRuns(result), [
          {
            'text': 'a',
            'marks': ['italic', 'code'],
            'href': '/guide',
          },
          {
            'text': 'bcde',
            'marks': ['italic', 'code', 'bold'],
            'href': '/guide',
          },
          {
            'text': 'f',
            'marks': ['italic', 'code'],
            'href': '/guide',
          },
        ]);
        expect(textRuns(body).single['marks'], ['italic', 'code']);
      },
    );

    test('cross-run selection keeps original edges and per-run metadata', () {
      final body = document([
        paragraph(
          'abcdefghi',
          runs: [
            {
              'text': 'abc',
              'marks': ['bold'],
              'href': '/first',
            },
            {'text': 'def', 'marks': <String>[]},
            {
              'text': 'ghi',
              'marks': ['italic'],
              'href': '/last',
            },
          ],
        ),
      ]);
      final result = select(
        body,
        1,
        8,
      ).setMark(body, 'underline', enabled: true);
      expect(textRuns(result), [
        {
          'text': 'a',
          'marks': ['bold'],
          'href': '/first',
        },
        {
          'text': 'bc',
          'marks': ['bold', 'underline'],
          'href': '/first',
        },
        {
          'text': 'def',
          'marks': ['underline'],
        },
        {
          'text': 'gh',
          'marks': ['italic', 'underline'],
          'href': '/last',
        },
        {
          'text': 'i',
          'marks': ['italic'],
          'href': '/last',
        },
      ]);
      expect(result.blocks.single['text'], 'abcdefghi');
    });

    test(
      'existing selected mark is not split while adjacent runs can change',
      () {
        final body = document([
          paragraph(
            'abcdef',
            runs: [
              {
                'text': 'abc',
                'marks': ['bold'],
              },
              {'text': 'def', 'href': '/doc'},
            ],
          ),
        ]);
        final result = select(body, 1, 5).setMark(body, 'bold', enabled: true);
        expect(textRuns(result), [
          {
            'text': 'abc',
            'marks': ['bold'],
          },
          {
            'text': 'de',
            'marks': ['bold'],
            'href': '/doc',
          },
          {'text': 'f', 'href': '/doc'},
        ]);
      },
    );

    test(
      'disabling one mark retains other marks, links and empty presence',
      () {
        final body = document([
          paragraph(
            'abcd',
            runs: [
              {
                'text': 'ab',
                'marks': ['bold'],
                'href': '/one',
              },
              {
                'text': 'cd',
                'marks': ['italic', 'bold', 'code'],
                'href': '/two',
              },
            ],
          ),
        ]);
        final result = select(body, 0, 4).setMark(body, 'bold', enabled: false);
        expect(textRuns(result), [
          {'text': 'ab', 'marks': <String>[], 'href': '/one'},
          {
            'text': 'cd',
            'marks': ['italic', 'code'],
            'href': '/two',
          },
        ]);
      },
    );

    test('absent and explicit empty marks remain distinct for a no-op', () {
      final body = document([
        paragraph(
          'ab',
          runs: [
            {'text': 'a'},
            {'text': 'b', 'marks': <String>[]},
          ],
        ),
      ]);
      final result = select(body, 0, 2).setMark(body, 'bold', enabled: false);
      expect(identical(result, body), isTrue);
      expect((textRuns(result)[0] as Map).containsKey('marks'), isFalse);
      expect((textRuns(result)[1] as Map).containsKey('marks'), isTrue);
    });

    test('no-op on plain text does not synthesize formatting', () {
      final body = document([paragraph('abc')]);
      expect(
        identical(
          select(body, 1, 2).setMark(body, 'bold', enabled: false),
          body,
        ),
        isTrue,
      );
      expect(body.blocks.single.containsKey('inlines'), isFalse);
    });

    for (final mark in StructuredInlineSelection.supportedMarks) {
      test('supported mark $mark can be enabled and disabled deliberately', () {
        final body = document([paragraph('words')]);
        final withMark = select(body, 1, 4).setMark(body, mark, enabled: true);
        expect(characterMarks(withMark).map((m) => m.contains(mark)), [
          false,
          true,
          true,
          true,
          false,
        ]);
        final without = select(
          withMark,
          1,
          4,
        ).setMark(withMark, mark, enabled: false);
        expect(characterMarks(without).every((m) => !m.contains(mark)), isTrue);
        expect(without.blocks.single['text'], 'words');
      });
    }

    test('invalid mark cannot change source or return partial edits', () {
      final body = document([paragraph('abc')]);
      final range = select(body, 0, 2);
      expect(
        () => range.setMark(body, 'highlight', enabled: true),
        throwsArgumentError,
      );
      expect(body.toJsonBlocks(), [paragraph('abc')]);
    });
  });

  group('links', () {
    test('sets a link across mixed existing runs without affecting marks', () {
      final body = document([
        paragraph(
          'abcdef',
          runs: [
            {
              'text': 'abc',
              'marks': ['bold'],
              'href': '/old',
            },
            {
              'text': 'def',
              'marks': ['italic'],
            },
          ],
        ),
      ]);
      final result = select(body, 1, 5).setLink(body, '/new');
      expect(textRuns(result), [
        {
          'text': 'a',
          'marks': ['bold'],
          'href': '/old',
        },
        {
          'text': 'bc',
          'marks': ['bold'],
          'href': '/new',
        },
        {
          'text': 'de',
          'marks': ['italic'],
          'href': '/new',
        },
        {
          'text': 'f',
          'marks': ['italic'],
        },
      ]);
    });

    test('removing a partial link keeps unselected portions linked', () {
      final body = document([
        paragraph(
          'abcd',
          runs: [
            {
              'text': 'abcd',
              'marks': ['code'],
              'href': '/target',
            },
          ],
        ),
      ]);
      final result = select(body, 1, 3).setLink(body, null);
      expect(textRuns(result), [
        {
          'text': 'a',
          'marks': ['code'],
          'href': '/target',
        },
        {
          'text': 'bc',
          'marks': ['code'],
        },
        {
          'text': 'd',
          'marks': ['code'],
          'href': '/target',
        },
      ]);
    });

    test('unchanged links and missing links do not cause run splits', () {
      final body = document([
        paragraph(
          'abc',
          runs: [
            {'text': 'abc', 'href': '/same'},
          ],
        ),
      ]);
      expect(
        identical(select(body, 1, 2).setLink(body, '/same'), body),
        isTrue,
      );
      final plain = document([paragraph('plain')]);
      expect(
        identical(select(plain, 0, 1).setLink(plain, null), plain),
        isTrue,
      );
      expect(plain.blocks.single.containsKey('inlines'), isFalse);
    });

    for (final href in [
      '',
      'javascript:alert(1)',
      'data:text/plain,abc',
      '//example.com/path',
      'https://user:password@example.com/',
      'https://example.com/a b',
      '/bad\\path',
      'relative/path',
      ' /space',
      '/${'x' * 2048}',
    ]) {
      test('rejects unsafe or invalid link ${jsonEncode(href)}', () {
        final body = document([paragraph('abc')]);
        expect(
          () => select(body, 0, 2).setLink(body, href),
          throwsFormatException,
        );
        expect(body.blocks.single.containsKey('inlines'), isFalse);
      });
    }

    test('preserves exact accepted link spelling without normalization', () {
      final body = document([paragraph('abc')]);
      for (final href in ['/guide?q=Yes#Part', 'https://example.com/A%20B']) {
        final result = select(body, 0, 3).setLink(body, href);
        expect(textRuns(result).single['href'], href);
      }
    });
  });

  group('list items and block integrity', () {
    test(
      'formatted item operation leaves other items byte-for-byte equivalent',
      () {
        final body = document([listBlock()]);
        final result = selectItem(
          body,
          1,
          1,
          3,
        ).setMark(body, 'code', enabled: true);
        expect(result.blocks.single['items'], ['alpha', 'beta', 'gamma']);
        expect(itemRuns(result, 0), itemRuns(body, 0));
        expect(itemRuns(result, 2), itemRuns(body, 2));
        expect(itemRuns(result, 1), [
          {'text': 'b', 'href': '/b'},
          {
            'text': 'e',
            'href': '/b',
            'marks': ['code'],
          },
          {
            'text': 't',
            'marks': ['italic', 'code'],
          },
          {
            'text': 'a',
            'marks': ['italic'],
          },
        ]);
        expect(result.blocks.single['ordered'], true);
      },
    );

    test(
      'link changes only selected list item and preserves all item strings',
      () {
        final body = document([listBlock()]);
        final result = selectItem(body, 0, 1, 4).setLink(body, '/new');
        expect(itemRuns(result, 1), itemRuns(body, 1));
        expect(itemRuns(result, 2), itemRuns(body, 2));
        expect(result.blocks.single['items'], body.blocks.single['items']);
        expect(textOfRuns(itemRuns(result, 0)), 'alpha');
        expect(itemRuns(result, 0), [
          {
            'text': 'a',
            'marks': ['bold'],
            'href': '/a',
          },
          {
            'text': 'l',
            'marks': ['bold'],
            'href': '/new',
          },
          {'text': 'ph', 'marks': <String>[], 'href': '/new'},
          {'text': 'a', 'marks': <String>[]},
        ]);
      },
    );

    test('plain list promotes all items only on a real change', () {
      final body = document([listBlock(formatted: false)]);
      final noOp = selectItem(
        body,
        1,
        1,
        3,
      ).setMark(body, 'bold', enabled: false);
      expect(identical(noOp, body), isTrue);
      expect(noOp.blocks.single.containsKey('itemInlines'), isFalse);
      final result = selectItem(
        body,
        1,
        1,
        3,
      ).setMark(body, 'bold', enabled: true);
      expect(itemRuns(result, 0), [
        {'text': 'alpha'},
      ]);
      expect(itemRuns(result, 1), [
        {'text': 'b'},
        {
          'text': 'et',
          'marks': ['bold'],
        },
        {'text': 'a'},
      ]);
      expect(itemRuns(result, 2), [
        {'text': 'gamma'},
      ]);
      expect(body.blocks.single.containsKey('itemInlines'), isFalse);
    });

    test('quote attribution and unrelated blocks never change', () {
      final body = fixture();
      final result = select(body, 2, 6, id: 'quote').setLink(body, '/new');
      for (var i = 0; i < body.blocks.length; i++) {
        if (body.blocks[i]['id'] != 'quote') {
          expect(result.blocks[i], body.blocks[i]);
        }
      }
      expect(result.blocks[3]['attribution'], 'Author name');
      expect(result.blocks[3]['text'], 'Quoted words');
      expect(result.blocks[1]['alt'], 'First image alt');
      expect(result.blocks[1]['caption'], 'First caption');
      expect(
        result.blocks.map((b) => b['id']),
        body.blocks.map((b) => b['id']),
      );
    });
  });

  group('stale selection fencing', () {
    test('an intervening target text change rejects the old range', () {
      final body = document([paragraph('abcdef')]);
      final range = select(body, 1, 4);
      final changed = body.replacePlainText('p', 'abcdef!');
      expect(
        () => range.setMark(changed, 'bold', enabled: true),
        throwsStateError,
      );
      expect(() => range.setLink(changed, '/x'), throwsStateError);
      expect(changed.blocks.single['text'], 'abcdef!');
      expect(changed.blocks.single.containsKey('inlines'), isFalse);
    });

    test('an intervening mark or link change rejects the old range', () {
      final body = document([
        paragraph(
          'abc',
          runs: [
            {
              'text': 'abc',
              'marks': ['bold'],
              'href': '/old',
            },
          ],
        ),
      ]);
      final range = select(body, 0, 2);
      final changed = body.setTextRunLink('p', 0, '/new');
      expect(
        () => range.setMark(changed, 'italic', enabled: true),
        throwsStateError,
      );
      expect(() => range.setLink(changed, '/old'), throwsStateError);
      expect(textRuns(changed).single['href'], '/new');
      expect(textRuns(changed).single['marks'], ['bold']);
    });

    test('unrelated changes also invalidate a selection conservatively', () {
      final body = fixture();
      final range = select(body, 0, 2, id: 'heading');
      final reordered = body.move('image-one', 2);
      final differentText = body.replacePlainText('paragraph', 'new text');
      final differentImage = body.replace('image-one', {
        ...body.blocks[1],
        'alt': 'new alt',
      });
      for (final stale in [reordered, differentText, differentImage]) {
        expect(
          () => range.setMark(stale, 'underline', enabled: true),
          throwsStateError,
        );
      }
      expect(body.blocks[1]['alt'], 'First image alt');
    });

    test('another structurally identical immutable snapshot is acceptable', () {
      final body = fixture();
      final clone = StructuredArticleDraft.parse(
        version: body.version,
        blocks: body.toJsonBlocks(),
      );
      expect(identical(body, clone), isFalse);
      final changed = select(
        body,
        0,
        2,
        id: 'heading',
      ).setMark(clone, 'code', enabled: true);
      expect(changed.blocks.first['text'], body.blocks.first['text']);
      expect(changed.blocks.skip(1), clone.blocks.skip(1));
    });

    test('reusing a selection after a successful mutation fails closed', () {
      final body = document([paragraph('abcdef')]);
      final range = select(body, 1, 5);
      final changed = range.setMark(body, 'bold', enabled: true);
      expect(() => range.setLink(changed, '/x'), throwsStateError);
      final newRange = select(changed, 1, 5);
      final linked = newRange.setLink(changed, '/x');
      expect(textRuns(linked)[1]['href'], '/x');
      expect(textRuns(linked)[1]['marks'], ['bold']);
    });

    test(
      'caller mutation of the original input cannot change captured selection',
      () {
        final blocks = [paragraph('abcdef')];
        final body = document(blocks);
        final range = select(body, 1, 3);
        blocks.single['text'] = 'mutated';
        blocks.add(paragraph('another'));
        final changed = range.setMark(body, 'italic', enabled: true);
        expect(changed.blocks.single['text'], 'abcdef');
        expect(textRuns(changed)[1], {
          'text': 'bc',
          'marks': ['italic'],
        });
      },
    );
  });

  group('bounded and immutable output', () {
    test(
      'never merges equal adjacent runs or changes unrelated optional keys',
      () {
        final body = document([
          paragraph(
            'abcd',
            runs: [
              {'text': 'ab', 'marks': <String>[]},
              {'text': 'cd', 'marks': <String>[]},
            ],
          ),
        ]);
        final changed = select(body, 0, 4).setMark(body, 'bold', enabled: true);
        expect(textRuns(changed), [
          {
            'text': 'ab',
            'marks': ['bold'],
          },
          {
            'text': 'cd',
            'marks': ['bold'],
          },
        ]);
        expect(() => changed.blocks.clear(), throwsUnsupportedError);
        expect(() => textRuns(changed).clear(), throwsUnsupportedError);
        expect(
          () => (textRuns(changed).first as Map)['text'] = 'x',
          throwsUnsupportedError,
        );
      },
    );

    test('up to exactly 1000 runs is accepted without normalization', () {
      final runs = <Object?>[
        {'text': 'xy'},
        for (var i = 0; i < 998; i++) {'text': 'z'},
      ];
      final body = document([paragraph('xy${'z' * 998}', runs: runs)]);
      final result = select(body, 0, 1).setMark(body, 'bold', enabled: true);
      expect(textRuns(result), hasLength(1000));
      expect(textRuns(result)[0], {
        'text': 'x',
        'marks': ['bold'],
      });
      expect(textRuns(result)[1], {'text': 'y'});
      expect(textOfRuns(textRuns(result)), body.blocks.single['text']);
    });

    test('exceeding 1000 runs rejects atomically rather than merging them', () {
      final runs = <Object?>[
        {'text': 'xyz'},
        for (var i = 0; i < 998; i++) {'text': 'a'},
      ];
      final body = document([paragraph('xyz${'a' * 998}', runs: runs)]);
      final before = jsonEncode(body.toJsonBlocks());
      expect(
        () => select(body, 1, 2).setMark(body, 'bold', enabled: true),
        throwsFormatException,
      );
      expect(
        () => select(body, 1, 2).setLink(body, '/x'),
        throwsFormatException,
      );
      expect(jsonEncode(body.toJsonBlocks()), before);
      expect(textRuns(body), hasLength(999));
    });

    test('an already formatted 1000-run no-op remains allowed', () {
      final body = document([
        paragraph(
          'a' * 1000,
          runs: [
            for (var i = 0; i < 1000; i++)
              {
                'text': 'a',
                'marks': ['bold'],
              },
          ],
        ),
      ]);
      final result = select(
        body,
        400,
        500,
      ).setMark(body, 'bold', enabled: true);
      expect(identical(result, body), isTrue);
      expect(textRuns(result), hasLength(1000));
    });

    test('full document JSON limit is enforced after an inline edit', () {
      final blocks = <Map<String, Object?>>[
        paragraph('abcdef'),
        for (var i = 0; i < 19; i++)
          {
            'id': 'c$i',
            'type': 'code',
            'language': 'text',
            'code': 'x' * 50000,
          },
        {'id': 'tail', 'type': 'code', 'language': 'text', 'code': ''},
      ];
      final remaining = 1000000 - jsonEncode(blocks).length - 10;
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(50000));
      blocks.last['code'] = 'z' * remaining;
      final body = document(blocks);
      final before = jsonEncode(body.toJsonBlocks());
      expect(before.length, 999990);
      expect(
        () => select(body, 2, 4).setMark(body, 'underline', enabled: true),
        throwsFormatException,
      );
      expect(jsonEncode(body.toJsonBlocks()), before);
    });

    test('run text and fallback preserve whitespace and literal markup', () {
      final body = document([paragraph('x **a**\n  b\t y')]);
      final result = select(body, 2, 7).setLink(body, '/literal');
      expect(result.blocks.single['text'], 'x **a**\n  b\t y');
      expect(textOfRuns(textRuns(result)), 'x **a**\n  b\t y');
      expect(textRuns(result)[1]['text'], '**a**');
    });
  });

  group('deterministic range properties', () {
    test('all ASCII intervals change only selected code units', () {
      const input = 'abcdefgh';
      for (var start = 0; start < input.length; start++) {
        for (var end = start + 1; end <= input.length; end++) {
          final body = document([
            paragraph(
              input,
              runs: [
                {
                  'text': 'ab',
                  'marks': ['italic'],
                  'href': '/a',
                },
                {
                  'text': 'cde',
                  'marks': ['code'],
                },
                {'text': 'fgh', 'href': '/b'},
              ],
            ),
          ]);
          final beforeMarks = characterMarks(body);
          final beforeLinks = characterLinks(body);
          final changed = select(
            body,
            start,
            end,
          ).setMark(body, 'bold', enabled: true);
          final afterMarks = characterMarks(changed);
          expect(changed.blocks.single['text'], input, reason: '$start..$end');
          expect(textOfRuns(textRuns(changed)), input, reason: '$start..$end');
          expect(characterLinks(changed), beforeLinks, reason: '$start..$end');
          for (var i = 0; i < input.length; i++) {
            final expected = {...beforeMarks[i]};
            if (i >= start && i < end) expected.add('bold');
            expect(afterMarks[i], expected, reason: '$start..$end at $i');
          }
        }
      }
    });

    test('all ASCII intervals change only selected links', () {
      const input = 'abcdefgh';
      for (var start = 0; start < input.length; start++) {
        for (var end = start + 1; end <= input.length; end++) {
          final body = document([
            paragraph(
              input,
              runs: [
                {
                  'text': 'ab',
                  'marks': ['italic'],
                  'href': '/a',
                },
                {
                  'text': 'cde',
                  'marks': ['code'],
                },
                {'text': 'fgh', 'href': '/b'},
              ],
            ),
          ]);
          final beforeMarks = characterMarks(body);
          final beforeLinks = characterLinks(body);
          final changed = select(body, start, end).setLink(body, '/selected');
          final afterLinks = characterLinks(changed);
          expect(characterMarks(changed), beforeMarks, reason: '$start..$end');
          for (var i = 0; i < input.length; i++) {
            expect(
              afterLinks[i],
              i >= start && i < end ? '/selected' : beforeLinks[i],
              reason: '$start..$end at $i',
            );
          }
          expect(textOfRuns(textRuns(changed)), input);
        }
      }
    });

    test(
      'seeded sequences maintain validated text, attributes and snapshots',
      () {
        final random = Random(232);
        var body = document([paragraph('abcdefghij')]);
        final history = <StructuredArticleDraft>[];
        for (var iteration = 0; iteration < 80; iteration++) {
          final start = random.nextInt(10);
          final end = start + 1 + random.nextInt(10 - start);
          final before = body;
          final range = select(before, start, end);
          if (iteration.isEven) {
            body = range.setMark(before, 'italic', enabled: random.nextBool());
          } else {
            body = range.setLink(before, random.nextBool() ? '/chosen' : null);
          }
          history.add(before);
          expect(body.blocks.single['text'], 'abcdefghij');
          if (body.blocks.single.containsKey('inlines')) {
            expect(textOfRuns(textRuns(body)), 'abcdefghij');
            expect(
              textRuns(body).every((run) => (run['text'] as String).isNotEmpty),
              isTrue,
            );
          }
          final encoded = body.toJsonBlocks();
          expect(
            StructuredArticleDraft.parse(
              version: 1,
              blocks: encoded,
            ).toJsonBlocks(),
            encoded,
          );
        }
        for (final previous in history) {
          expect(previous.blocks.single['text'], 'abcdefghij');
        }
      },
    );
  });
}
