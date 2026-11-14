import 'dart:convert';
import 'dart:math';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_inline_replacement.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

StructuredArticleDraft document(
  List<Map<String, Object?>> blocks, {
  int version = 1,
}) => StructuredArticleDraft.parse(version: version, blocks: blocks);

Map<String, Object?> paragraph({
  String text = 'abcdefgh',
  bool formatted = true,
}) => {
  'id': 'p',
  'type': 'paragraph',
  'text': text,
  if (formatted)
    'inlines': [
      {
        'text': 'abc',
        'marks': ['bold'],
        'href': '/first',
      },
      {'text': 'de', 'marks': <String>[]},
      {
        'text': 'fgh',
        'marks': ['italic', 'code'],
        'href': 'https://example.org/end',
      },
    ],
};

Map<String, Object?> list({bool formatted = true}) => {
  'id': 'l',
  'type': 'list',
  'ordered': true,
  'items': ['alpha', ' beta ', 'gamma'],
  if (formatted)
    'itemInlines': [
      [
        {
          'text': 'al',
          'marks': ['bold'],
          'href': '/one',
        },
        {'text': 'pha'},
      ],
      [
        {'text': ' be', 'href': '/two'},
        {
          'text': 'ta ',
          'marks': ['italic'],
        },
      ],
      [
        {'text': 'gamma', 'marks': <String>[]},
      ],
    ],
};

StructuredArticleDraft fixture() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredInlineReplacement capture(
  StructuredArticleDraft body,
  int start,
  int end, {
  String id = 'p',
}) => StructuredInlineReplacement.textBlock(
  document: body,
  blockId: id,
  start: start,
  end: end,
);

StructuredInlineReplacement captureItem(
  StructuredArticleDraft body,
  int item,
  int start,
  int end, {
  String id = 'l',
}) => StructuredInlineReplacement.listItem(
  document: body,
  blockId: id,
  itemIndex: item,
  start: start,
  end: end,
);

StructuredInsertedText insert(
  String text, {
  List<String>? marks,
  String? href,
}) => StructuredInsertedText(text: text, marks: marks, href: href);

Map<String, Object?> block(StructuredArticleDraft body, String id) =>
    body.blocks.firstWhere((value) => value['id'] == id);
List<dynamic> runs(StructuredArticleDraft body, {String id = 'p'}) =>
    block(body, id)['inlines'] as List;
List<dynamic> itemRuns(
  StructuredArticleDraft body,
  int item, {
  String id = 'l',
}) => (block(body, id)['itemInlines'] as List)[item] as List;
String joined(List<dynamic> runs) =>
    runs.map((r) => r['text'] as String).join();

/// Independent per-code-unit oracle retaining presence, order, and links.
List<Map<String, Object?>> units(List<dynamic> input) => [
  for (final raw in input)
    for (var i = 0; i < (raw['text'] as String).length; i++)
      {
        'unit': (raw['text'] as String).codeUnitAt(i),
        if ((raw as Map).containsKey('marks')) 'marks': raw['marks'],
        if (raw.containsKey('href')) 'href': raw['href'],
      },
];

void main() {
  group('capture and target validation', () {
    test('captures a text range including a collapsed insertion', () {
      final body = document([paragraph()]);
      final edit = capture(body, 3, 3);
      expect(edit.blockId, 'p');
      expect(edit.itemIndex, isNull);
      expect(edit.start, 3);
      expect(edit.end, 3);
      expect(edit.text, 'abcdefgh');
      expect(body.blocks.single['text'], 'abcdefgh');
    });

    test('captures a list index and preserves the exact fallback', () {
      final body = document([list()]);
      final edit = captureItem(body, 1, 0, 6);
      expect(edit.blockId, 'l');
      expect(edit.itemIndex, 1);
      expect(edit.text, ' beta ');
      expect(edit.start, 0);
      expect(edit.end, 6);
    });

    test('supports heading and quote without changing optional metadata', () {
      final body = fixture();
      for (final id in ['heading', 'paragraph', 'quote']) {
        final target = block(body, id);
        final source = target['text'] as String;
        final edited = capture(
          body,
          0,
          0,
          id: id,
        ).apply(body, inserted: insert('X'));
        expect(block(edited, id)['text'], 'X$source');
        for (final field in ['id', 'type', 'level', 'attribution']) {
          expect(
            block(edited, id).containsKey(field),
            target.containsKey(field),
          );
          expect(block(edited, id)[field], target[field]);
        }
        expect(
          edited.blocks.where((b) => b['id'] != id).toList(),
          body.blocks.where((b) => b['id'] != id).toList(),
        );
      }
    });

    test('rejects v0 instead of silently upgrading', () {
      final body = document([
        paragraph(text: 'plain', formatted: false),
        list(formatted: false),
      ], version: 0);
      expect(() => capture(body, 0, 0), throwsStateError);
      expect(() => captureItem(body, 0, 0, 0), throwsStateError);
      expect(body.version, 0);
      expect(body.blocks.first.containsKey('inlines'), isFalse);
      expect(body.blocks.last.containsKey('itemInlines'), isFalse);
    });

    test('rejects missing and wrong-type targets', () {
      final body = document([
        paragraph(),
        list(),
        {'id': 'image', 'type': 'image', 'src': '/image', 'alt': ''},
      ]);
      expect(() => capture(body, 0, 1, id: 'missing'), throwsArgumentError);
      expect(() => capture(body, 0, 1, id: 'l'), throwsArgumentError);
      expect(() => capture(body, 0, 1, id: 'image'), throwsArgumentError);
      expect(() => captureItem(body, 0, 0, 1, id: 'p'), throwsArgumentError);
      expect(
        () => captureItem(body, 0, 0, 1, id: 'image'),
        throwsArgumentError,
      );
      expect(
        () => captureItem(body, 0, 0, 1, id: 'missing'),
        throwsArgumentError,
      );
    });

    test('rejects invalid list indices and UTF-16 ranges', () {
      final body = document([paragraph(), list()]);
      expect(() => captureItem(body, -1, 0, 0), throwsRangeError);
      expect(() => captureItem(body, 3, 0, 0), throwsRangeError);
      for (final pair in [
        [-1, 0],
        [0, 9],
        [2, 1],
        [9, 9],
        [0, -1],
      ]) {
        expect(() => capture(body, pair[0], pair[1]), throwsRangeError);
      }
      for (final pair in [
        [-1, 0],
        [0, 7],
        [2, 1],
        [7, 7],
      ]) {
        expect(() => captureItem(body, 1, pair[0], pair[1]), throwsRangeError);
      }
    });

    test('allows both ends and rejects splitting a surrogate pair', () {
      final body = document([paragraph(text: 'A😀B', formatted: false)]);
      expect(capture(body, 0, 0).start, 0);
      expect(capture(body, 4, 4).end, 4);
      expect(() => capture(body, 2, 2), throwsFormatException);
      expect(() => capture(body, 0, 2), throwsFormatException);
      expect(() => capture(body, 2, 4), throwsFormatException);
      expect(capture(body, 1, 3).text.substring(1, 3), '😀');
    });

    test('checks fallback even when a surrogate pair spans runs', () {
      final high = '😀'.substring(0, 1);
      final low = '😀'.substring(1);
      final body = document([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'A$high${low}B',
          'inlines': [
            {'text': 'A$high', 'href': '/one'},
            {'text': '${low}B'},
          ],
        },
      ]);
      expect(() => capture(body, 2, 2), throwsFormatException);
      final result = capture(body, 1, 3).apply(body, inserted: insert('C'));
      expect(block(result, 'p')['text'], 'ACB');
      expect(runs(result), [
        {'text': 'A', 'href': '/one'},
        {'text': 'C'},
        {'text': 'B'},
      ]);
    });

    test('unpaired target surrogate is refused rather than repaired', () {
      final high = '😀'.substring(0, 1);
      final body = document([paragraph(text: 'A$high', formatted: false)]);
      expect(() => capture(body, 0, 1), throwsFormatException);
      expect(block(body, 'p')['text'], 'A$high');
      expect(block(body, 'p').containsKey('inlines'), isFalse);
    });

    test('combining sequences are not promised as grapheme boundaries', () {
      final body = document([paragraph(text: 'Ae\u0301B', formatted: false)]);
      final result = capture(body, 2, 3).apply(body);
      expect(block(result, 'p')['text'], 'AeB');
      expect(block(body, 'p')['text'], 'Ae\u0301B');
    });
  });

  group('explicit inserted values', () {
    test('rejects empty, oversized and unpaired input', () {
      final high = '😀'.substring(0, 1);
      final low = '😀'.substring(1);
      expect(() => insert(''), throwsFormatException);
      expect(() => insert('a' * 20001), throwsFormatException);
      expect(() => insert(high), throwsFormatException);
      expect(() => insert(low), throwsFormatException);
      expect(() => insert('x$high'), throwsFormatException);
      expect(insert('😀').text, '😀');
      expect(insert('a' * 20000).text.length, 20000);
    });

    test('accepts supported marks in explicit order including empty', () {
      final value = insert(
        'x',
        marks: ['code', 'bold', 'italic', 'underline', 'strikethrough'],
      );
      expect(value.marks, [
        'code',
        'bold',
        'italic',
        'underline',
        'strikethrough',
      ]);
      expect(insert('x', marks: []).marks, isEmpty);
      expect(insert('x').marks, isNull);
    });

    test('rejects unknown duplicate and oversized marks', () {
      expect(() => insert('x', marks: ['unknown']), throwsFormatException);
      expect(() => insert('x', marks: ['bold', 'bold']), throwsFormatException);
      expect(
        () => insert(
          'x',
          marks: [
            'bold',
            'italic',
            'underline',
            'code',
            'strikethrough',
            'bold',
          ],
        ),
        throwsFormatException,
      );
      expect(() => insert('x', marks: ['']), throwsFormatException);
    });

    test('insertion owns an immutable copy of the marks', () {
      final original = ['bold', 'italic'];
      final value = insert('X', marks: original, href: '/safe');
      original[0] = 'code';
      original.add('underline');
      expect(value.marks, ['bold', 'italic']);
      expect(() => value.marks!.add('code'), throwsUnsupportedError);
      final body = document([paragraph()]);
      final result = capture(body, 1, 1).apply(body, inserted: value);
      expect(runs(result)[1], {
        'text': 'X',
        'marks': ['bold', 'italic'],
        'href': '/safe',
      });
    });

    test('accepts safe exact links without normalizing them', () {
      for (final url in [
        '/path?q=1#top',
        'https://example.org/A%20B',
        'http://example.org:8080/path',
      ]) {
        expect(insert('x', href: url).href, url);
      }
    });

    test('rejects unsafe, credentialed, whitespace and malformed links', () {
      final high = '😀'.substring(0, 1);
      for (final url in [
        '',
        '//example.org',
        'javascript:alert(1)',
        'https://u:p@example.org',
        '/has space',
        '/x\\y',
        '/bad$high',
      ]) {
        expect(
          () => insert('x', href: url),
          throwsFormatException,
          reason: url,
        );
      }
    });
  });

  group('text replacement and exact preservation', () {
    test(
      'plain insertion within a formatted run never inherits attributes',
      () {
        final body = document([paragraph()]);
        final result = capture(body, 1, 1).apply(body, inserted: insert('X'));
        expect(block(result, 'p')['text'], 'aXbcdefgh');
        expect(runs(result), [
          {
            'text': 'a',
            'marks': ['bold'],
            'href': '/first',
          },
          {'text': 'X'},
          {
            'text': 'bc',
            'marks': ['bold'],
            'href': '/first',
          },
          {'text': 'de', 'marks': <String>[]},
          {
            'text': 'fgh',
            'marks': ['italic', 'code'],
            'href': 'https://example.org/end',
          },
        ]);
        expect(block(body, 'p')['text'], 'abcdefgh');
      },
    );

    test('insertion at a run boundary never chooses left or right style', () {
      final body = document([paragraph()]);
      final result = capture(body, 3, 3).apply(
        body,
        inserted: insert('X', marks: ['underline'], href: '/chosen'),
      );
      expect(runs(result), [
        {
          'text': 'abc',
          'marks': ['bold'],
          'href': '/first',
        },
        {
          'text': 'X',
          'marks': ['underline'],
          'href': '/chosen',
        },
        {'text': 'de', 'marks': <String>[]},
        {
          'text': 'fgh',
          'marks': ['italic', 'code'],
          'href': 'https://example.org/end',
        },
      ]);
    });

    test('insertion at both document edges keeps all original runs', () {
      final body = document([paragraph()]);
      final before = capture(body, 0, 0).apply(body, inserted: insert('X'));
      final after = capture(body, 8, 8).apply(body, inserted: insert('Y'));
      expect(runs(before).first, {'text': 'X'});
      expect(runs(before).skip(1).toList(), runs(body));
      expect(runs(after).last, {'text': 'Y'});
      expect(runs(after).take(3).toList(), runs(body));
      expect(block(before, 'p')['text'], 'Xabcdefgh');
      expect(block(after, 'p')['text'], 'abcdefghY');
    });

    test('replacement across three runs preserves only outside attributes', () {
      final body = document([paragraph()]);
      final result = capture(body, 1, 7).apply(
        body,
        inserted: insert('NEW', marks: ['code'], href: '/new'),
      );
      expect(block(result, 'p')['text'], 'aNEWh');
      expect(runs(result), [
        {
          'text': 'a',
          'marks': ['bold'],
          'href': '/first',
        },
        {
          'text': 'NEW',
          'marks': ['code'],
          'href': '/new',
        },
        {
          'text': 'h',
          'marks': ['italic', 'code'],
          'href': 'https://example.org/end',
        },
      ]);
      expect(runs(body).length, 3);
    });

    test('deletion across boundaries keeps untouched optional keys', () {
      final body = document([paragraph()]);
      final result = capture(body, 2, 6).apply(body);
      expect(block(result, 'p')['text'], 'abgh');
      expect(runs(result), [
        {
          'text': 'ab',
          'marks': ['bold'],
          'href': '/first',
        },
        {
          'text': 'gh',
          'marks': ['italic', 'code'],
          'href': 'https://example.org/end',
        },
      ]);
    });

    test('deleting one run does not merge equal adjacent runs', () {
      final body = document([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'abc',
          'inlines': [
            {
              'text': 'a',
              'marks': ['bold'],
            },
            {'text': 'b'},
            {
              'text': 'c',
              'marks': ['bold'],
            },
          ],
        },
      ]);
      final result = capture(body, 1, 2).apply(body);
      expect(runs(result), [
        {
          'text': 'a',
          'marks': ['bold'],
        },
        {
          'text': 'c',
          'marks': ['bold'],
        },
      ]);
    });

    test('explicit empty marks remain distinct from absent marks', () {
      final body = document([paragraph()]);
      final result = capture(
        body,
        3,
        5,
      ).apply(body, inserted: insert('D', marks: []));
      expect(runs(result)[1], {'text': 'D', 'marks': <String>[]});
      final plain = capture(body, 3, 5).apply(body, inserted: insert('D'));
      expect(runs(plain)[1], {'text': 'D'});
      expect((runs(plain)[1] as Map).containsKey('marks'), isFalse);
    });

    test('same text can deliberately replace formatting', () {
      final body = document([paragraph()]);
      final result = capture(body, 0, 3).apply(body, inserted: insert('abc'));
      expect(block(result, 'p')['text'], 'abcdefgh');
      expect(runs(result).first, {'text': 'abc'});
      expect(runs(result).skip(1).toList(), runs(body).skip(1).toList());
    });

    test('empty edit returns identical body even at the run limit', () {
      final body = document([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'x' * 1000,
          'inlines': [
            for (var i = 0; i < 1000; i++) {'text': 'x'},
          ],
        },
      ]);
      expect(identical(capture(body, 500, 500).apply(body), body), isTrue);
      expect(runs(body).length, 1000);
    });

    test('plain paragraph stays plain for replacement and deletion', () {
      final body = document([paragraph(text: 'alpha', formatted: false)]);
      final replaced = capture(body, 1, 4).apply(body, inserted: insert('ZZ'));
      final deleted = capture(body, 1, 4).apply(body);
      expect(block(replaced, 'p')['text'], 'aZZa');
      expect(block(deleted, 'p')['text'], 'aa');
      expect(block(replaced, 'p').containsKey('inlines'), isFalse);
      expect(block(deleted, 'p').containsKey('inlines'), isFalse);
      expect(
        identical(
          capture(body, 1, 4).apply(body, inserted: insert('lph')),
          body,
        ),
        isTrue,
      );
    });

    test('styled insertion promotes a plain paragraph explicitly', () {
      final body = document([paragraph(text: 'alpha', formatted: false)]);
      final result = capture(
        body,
        1,
        4,
      ).apply(body, inserted: insert('X', marks: ['bold']));
      expect(block(result, 'p')['text'], 'aXa');
      expect(runs(result), [
        {'text': 'a'},
        {
          'text': 'X',
          'marks': ['bold'],
        },
        {'text': 'a'},
      ]);
      expect(block(body, 'p').containsKey('inlines'), isFalse);
    });

    test(
      'deleting whole content fails instead of losing invalid intermediate',
      () {
        for (final formatted in [false, true]) {
          final body = document([
            paragraph(
              text: formatted ? 'abcdefgh' : 'plain',
              formatted: formatted,
            ),
          ]);
          final length = (block(body, 'p')['text'] as String).length;
          expect(
            () => capture(body, 0, length).apply(body),
            throwsFormatException,
          );
          expect(block(body, 'p')['text'], formatted ? 'abcdefgh' : 'plain');
        }
      },
    );

    test(
      'edge whitespace and whitespace-only paragraph are not silently trimmed',
      () {
        final body = document([paragraph(text: 'abc', formatted: false)]);
        expect(
          () => capture(body, 0, 0).apply(body, inserted: insert(' ')),
          throwsFormatException,
        );
        expect(
          () => capture(body, 3, 3).apply(body, inserted: insert(' ')),
          throwsFormatException,
        );
        expect(
          () => capture(body, 0, 3).apply(body, inserted: insert('  ')),
          throwsFormatException,
        );
        expect(block(body, 'p')['text'], 'abc');
      },
    );

    test(
      'literal Markdown, newlines and explicit links are not interpreted',
      () {
        final body = document([paragraph(text: 'abc', formatted: false)]);
        final result = capture(
          body,
          1,
          2,
        ).apply(body, inserted: insert('**x**\n[y](z)', href: '/exact'));
        expect(block(result, 'p')['text'], 'a**x**\n[y](z)c');
        expect(runs(result)[1], {'text': '**x**\n[y](z)', 'href': '/exact'});
      },
    );
  });

  group('list item replacement', () {
    test('plain item replacement preserves absence of itemInlines', () {
      final body = document([list(formatted: false)]);
      final result = captureItem(
        body,
        1,
        1,
        5,
      ).apply(body, inserted: insert('text'));
      expect(block(result, 'l')['items'], ['alpha', ' text ', 'gamma']);
      expect(block(result, 'l').containsKey('itemInlines'), isFalse);
      expect(block(body, 'l')['items'], ['alpha', ' beta ', 'gamma']);
    });

    test('formatted insertion promotes every plain item losslessly', () {
      final body = document([list(formatted: false)]);
      final result = captureItem(body, 1, 1, 5).apply(
        body,
        inserted: insert('X', marks: ['bold'], href: '/x'),
      );
      expect(block(result, 'l')['items'], ['alpha', ' X ', 'gamma']);
      expect(block(result, 'l')['itemInlines'], [
        [
          {'text': 'alpha'},
        ],
        [
          {'text': ' '},
          {
            'text': 'X',
            'marks': ['bold'],
            'href': '/x',
          },
          {'text': ' '},
        ],
        [
          {'text': 'gamma'},
        ],
      ]);
      expect(block(result, 'l')['ordered'], true);
      expect(block(body, 'l').containsKey('itemInlines'), isFalse);
    });

    test('replaces across runs in only the selected item', () {
      final body = document([list()]);
      final result = captureItem(
        body,
        1,
        2,
        4,
      ).apply(body, inserted: insert('XX', marks: ['code']));
      expect(block(result, 'l')['items'], ['alpha', ' bXXa ', 'gamma']);
      expect(itemRuns(result, 0), itemRuns(body, 0));
      expect(itemRuns(result, 1), [
        {'text': ' b', 'href': '/two'},
        {
          'text': 'XX',
          'marks': ['code'],
        },
        {
          'text': 'a ',
          'marks': ['italic'],
        },
      ]);
      expect(itemRuns(result, 2), itemRuns(body, 2));
      expect(block(result, 'l')['ordered'], block(body, 'l')['ordered']);
    });

    test(
      'list permits item whitespace but rejects empty or whitespace-only',
      () {
        final body = document([list()]);
        final result = captureItem(
          body,
          1,
          0,
          0,
        ).apply(body, inserted: insert(' '));
        expect((block(result, 'l')['items'] as List)[1], '  beta ');
        expect(
          () => captureItem(body, 1, 0, 6).apply(body),
          throwsFormatException,
        );
        expect(
          () => captureItem(body, 1, 0, 6).apply(body, inserted: insert('  ')),
          throwsFormatException,
        );
        expect((block(body, 'l')['items'] as List)[1], ' beta ');
      },
    );

    test('plain list item remains unchanged for an equal replacement', () {
      final body = document([list(formatted: false)]);
      final result = captureItem(
        body,
        0,
        1,
        4,
      ).apply(body, inserted: insert('lph'));
      expect(identical(result, body), isTrue);
      expect(block(body, 'l').containsKey('itemInlines'), isFalse);
    });

    test(
      'unrelated blocks, images and order survive a formatted list edit',
      () {
        final body = fixture();
        final edit = captureItem(body, 1, 1, 7, id: 'list');
        final result = edit.apply(
          body,
          inserted: insert('replacement', href: '/target'),
        );
        expect(
          result.blocks.map((b) => b['id']).toList(),
          body.blocks.map((b) => b['id']).toList(),
        );
        expect(
          result.blocks.where((b) => b['id'] != 'list').toList(),
          body.blocks.where((b) => b['id'] != 'list').toList(),
        );
        expect(itemRuns(result, 0, id: 'list'), itemRuns(body, 0, id: 'list'));
        expect(
          block(result, 'list')['ordered'],
          block(body, 'list')['ordered'],
        );
        expect(
          block(result, 'image-one')['alt'],
          block(body, 'image-one')['alt'],
        );
        expect(
          block(result, 'image-two')['caption'],
          block(body, 'image-two')['caption'],
        );
      },
    );

    test('list item supports complete emoji replacement', () {
      final body = document([
        {
          'id': 'l',
          'type': 'list',
          'ordered': false,
          'items': ['A😀B', 'other'],
        },
      ]);
      expect(() => captureItem(body, 0, 2, 2), throwsFormatException);
      final result = captureItem(
        body,
        0,
        1,
        3,
      ).apply(body, inserted: insert('文', marks: ['italic']));
      expect(block(result, 'l')['items'], ['A文B', 'other']);
      expect(itemRuns(result, 0), [
        {'text': 'A'},
        {
          'text': '文',
          'marks': ['italic'],
        },
        {'text': 'B'},
      ]);
      expect(itemRuns(result, 1), [
        {'text': 'other'},
      ]);
    });
  });

  group('snapshot fencing and immutability', () {
    test(
      'all changes including other blocks make a captured operation stale',
      () {
        final body = fixture();
        final edit = capture(body, 1, 3, id: 'heading');
        final changed = [
          body.move('image-two', 1),
          body.replacePlainText('paragraph', 'changed'),
          body.setTextRunMark('quote', 0, 'code', enabled: true),
          body.replace('image-one', {
            ...block(body, 'image-one'),
            'alt': 'other',
          }),
        ];
        for (final current in changed) {
          expect(
            () => edit.apply(current, inserted: insert('X')),
            throwsStateError,
          );
          expect(() => edit.apply(current), throwsStateError);
          expect(() => edit.apply(current, inserted: null), throwsStateError);
        }
        expect(body.toJsonBlocks(), fixture().toJsonBlocks());
      },
    );

    test('list item reordering cannot redirect the captured index', () {
      final body = document([list()]);
      final edit = captureItem(body, 0, 1, 3);
      final original = block(body, 'l');
      final reordered = body.replace('l', {
        ...original,
        'items': (original['items'] as List).reversed.toList(),
        'itemInlines': (original['itemInlines'] as List).reversed.toList(),
      });
      expect(
        () => edit.apply(reordered, inserted: insert('X')),
        throwsStateError,
      );
      expect(block(reordered, 'l')['items'], ['gamma', ' beta ', 'alpha']);
      expect(itemRuns(reordered, 2), itemRuns(body, 0));
    });

    test(
      'serialized-equivalent body is allowed but is not an account fence',
      () {
        final body = document([paragraph()]);
        final copy = StructuredArticleDraft.parse(
          version: body.version,
          blocks: body.toJsonBlocks(),
        );
        expect(identical(copy, body), isFalse);
        final edit = capture(body, 2, 4);
        final result = edit.apply(copy, inserted: insert('X'));
        expect(block(result, 'p')['text'], 'abXefgh');
        expect(body.toJsonBlocks(), copy.toJsonBlocks());
      },
    );

    test(
      'captured replacement remains independent of detached caller data',
      () {
        final source = paragraph();
        final body = document([source]);
        final edit = capture(body, 1, 2);
        source['text'] = 'changed';
        final sourceRuns = source['inlines'] as List;
        (sourceRuns.first as Map)['href'] = '/mutated';
        final result = edit.apply(body, inserted: insert('X'));
        expect(block(body, 'p')['text'], 'abcdefgh');
        expect(runs(result).first['href'], '/first');
        expect(block(result, 'p')['text'], 'aXcdefgh');
      },
    );

    test('stale check happens even for an empty no-op', () {
      final body = document([paragraph()]);
      final edit = capture(body, 0, 0);
      final changed = body.setTextRunMark('p', 0, 'italic', enabled: true);
      expect(() => edit.apply(changed), throwsStateError);
      expect(runs(changed).first['marks'], ['bold', 'italic']);
    });

    test('output is detached and serialized content round trips exactly', () {
      final body = document([paragraph(), list()]);
      final result = capture(body, 2, 6).apply(
        body,
        inserted: insert('😀', marks: ['underline'], href: '/x'),
      );
      final encoded = jsonEncode(result.toJsonBlocks());
      final parsed = StructuredArticleDraft.parse(
        version: result.version,
        blocks: jsonDecode(encoded),
      );
      expect(parsed.toJsonBlocks(), result.toJsonBlocks());
      final detached = result.toJsonBlocks();
      (detached.first['inlines'] as List).clear();
      expect(runs(result).length, greaterThan(0));
      expect(block(result, 'p')['text'], 'ab😀gh');
    });
  });

  group('document limits and fail-closed behavior', () {
    test('1000 runs cannot grow through an insertion', () {
      final body = document([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'x' * 1000,
          'inlines': [
            for (var i = 0; i < 1000; i++) {'text': 'x', 'href': '/$i'},
          ],
        },
      ]);
      expect(
        () => capture(body, 500, 500).apply(body, inserted: insert('X')),
        throwsFormatException,
      );
      expect(runs(body).length, 1000);
      expect(block(body, 'p')['text'], 'x' * 1000);
    });

    test('deleting a run creates room without silently merging neighbors', () {
      final body = document([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'x' * 1000,
          'inlines': [
            for (var i = 0; i < 1000; i++) {'text': 'x', 'href': '/$i'},
          ],
        },
      ]);
      final deleted = capture(body, 100, 101).apply(body);
      expect(runs(deleted).length, 999);
      expect(runs(deleted)[99]['href'], '/99');
      expect(runs(deleted)[100]['href'], '/101');
      final inserted = capture(
        deleted,
        100,
        100,
      ).apply(deleted, inserted: insert('Y'));
      expect(runs(inserted).length, 1000);
      expect(block(inserted, 'p')['text'], '${'x' * 100}Y${'x' * 899}');
    });

    test('text block length limit is checked before returning a document', () {
      final body = document([paragraph(text: 'x' * 20000, formatted: false)]);
      expect(
        () => capture(body, 1, 1).apply(body, inserted: insert('Y')),
        throwsFormatException,
      );
      final result = capture(body, 1, 2).apply(body, inserted: insert('Y'));
      expect((block(result, 'p')['text'] as String).length, 20000);
      expect(block(body, 'p')['text'], 'x' * 20000);
    });

    test('list item length limit is independent of paragraph limit', () {
      final body = document([
        {
          'id': 'l',
          'type': 'list',
          'ordered': false,
          'items': ['x' * 2000],
        },
      ]);
      expect(
        () => captureItem(body, 0, 1, 1).apply(body, inserted: insert('Y')),
        throwsFormatException,
      );
      final result = captureItem(
        body,
        0,
        1,
        2,
      ).apply(body, inserted: insert('Y'));
      expect(
        ((block(result, 'l')['items'] as List).single as String).length,
        2000,
      );
      expect((block(body, 'l')['items'] as List).single, 'x' * 2000);
    });

    test('document JSON cap remains enforced without modifying the source', () {
      final body = document([
        for (var i = 0; i < 19; i++)
          {
            'id': 'c$i',
            'type': 'code',
            'language': 'dart',
            'code': 'x' * 50000,
          },
        {'id': 'last', 'type': 'code', 'language': 'dart', 'code': 'x' * 29500},
        paragraph(text: 'a' * 19000, formatted: false),
      ]);
      final original = jsonEncode(body.toJsonBlocks());
      expect(original.length, greaterThan(999500));
      expect(original.length, lessThanOrEqualTo(1000000));
      expect(
        () => capture(body, 1, 1).apply(body, inserted: insert('b' * 500)),
        throwsFormatException,
      );
      expect(jsonEncode(body.toJsonBlocks()), original);
    });

    test('rejected replacements do not change a prior successful snapshot', () {
      final body = document([paragraph()]);
      final good = capture(body, 1, 3).apply(body, inserted: insert('X'));
      final before = jsonEncode(good.toJsonBlocks());
      final length = (block(good, 'p')['text'] as String).length;
      expect(() => capture(good, 0, length).apply(good), throwsFormatException);
      expect(jsonEncode(good.toJsonBlocks()), before);
      expect(block(body, 'p')['text'], 'abcdefgh');
    });
  });

  group('independent randomized preservation oracle', () {
    test(
      '500 varied replacements preserve every unselected code unit and attribute',
      () {
        final random = Random(232243);
        final body = document([paragraph()]);
        final oldUnits = units(runs(body));
        for (var trial = 0; trial < 500; trial++) {
          final start = random.nextInt(9);
          final end = start + random.nextInt(9 - start);
          final chosen = switch (random.nextInt(4)) {
            0 => insert('X'),
            1 => insert('YZ', marks: []),
            2 => insert('123', marks: ['code', 'italic'], href: '/chosen'),
            _ => insert('文', href: 'https://example.org/'),
          };
          final result = capture(
            body,
            start,
            end,
          ).apply(body, inserted: chosen);
          final expected = [
            ...oldUnits.sublist(0, start),
            ...units([
              {
                'text': chosen.text,
                if (chosen.marks != null) 'marks': chosen.marks,
                if (chosen.href != null) 'href': chosen.href,
              },
            ]),
            ...oldUnits.sublist(end),
          ];
          expect(
            units(runs(result)),
            expected,
            reason: 'trial $trial, $start..$end',
          );
          expect(
            block(result, 'p')['text'],
            'abcdefgh'.substring(0, start) +
                chosen.text +
                'abcdefgh'.substring(end),
          );
          expect(joined(runs(result)), block(result, 'p')['text']);
        }
        expect(block(body, 'p')['text'], 'abcdefgh');
      },
    );

    test(
      '100 sequential replacements use fresh snapshots and exact attributes',
      () {
        final random = Random(991);
        var body = document([paragraph()]);
        for (var trial = 0; trial < 100; trial++) {
          final previous = body;
          final text = block(previous, 'p')['text'] as String;
          final start = random.nextInt(text.length + 1);
          final end = start + random.nextInt(text.length - start + 1);
          final oldUnits = units(runs(previous));
          final value = insert(
            trial.isEven ? 'AB' : 'Z',
            marks: trial.isEven ? ['bold'] : [],
            href: trial.isEven ? '/a' : null,
          );
          body = capture(previous, start, end).apply(previous, inserted: value);
          final expected = [
            ...oldUnits.sublist(0, start),
            ...units([
              {
                'text': value.text,
                'marks': value.marks,
                if (value.href != null) 'href': value.href,
              },
            ]),
            ...oldUnits.sublist(end),
          ];
          expect(units(runs(body)), expected, reason: 'trial $trial');
          expect(
            block(body, 'p')['text'],
            text.substring(0, start) + value.text + text.substring(end),
          );
          expect(block(previous, 'p')['text'], text);
        }
      },
    );
  });
}
