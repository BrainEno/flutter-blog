import 'dart:convert';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
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

Map<String, Object?> paragraph(String id, String text) => {
  'id': id,
  'type': 'paragraph',
  'text': text,
};

void main() {
  group('lossless snapshots', () {
    test(
      'all supported blocks, optional fields and exact inline runs survive',
      () {
        final original = structuredArticle();
        final draft = fixture();
        expect(draft.version, 1);
        expect(draft.toJsonBlocks(), original['contentBlocks']);
        expect(draft.blocks.map((block) => block['id']), [
          'heading',
          'image-one',
          'paragraph',
          'quote',
          'list',
          'image-two',
          'code',
        ]);
        final code = draft.blocks.last;
        expect(code['code'], r'  a\n\n b  \n');
        final image = draft.blocks[1];
        expect(image['src'], '/media/one.png');
        expect(image['alt'], 'First image alt');
        expect(image['caption'], 'First caption');
      },
    );

    test('missing and present empty optional properties remain distinct', () {
      final blocks = <Map<String, Object?>>[
        {'id': 'a', 'type': 'image', 'src': '/a', 'alt': ''},
        {'id': 'b', 'type': 'image', 'src': '/b', 'alt': '', 'caption': ''},
        {'id': 'c', 'type': 'quote', 'text': 'quote'},
        {'id': 'd', 'type': 'quote', 'text': 'quote', 'attribution': ''},
        {'id': 'e', 'type': 'paragraph', 'text': 'same'},
        {
          'id': 'f',
          'type': 'paragraph',
          'text': 'same',
          'inlines': [
            {'text': 'same', 'marks': <String>[]},
          ],
        },
      ];
      final saved = document(blocks).toJsonBlocks();
      expect(saved, blocks);
      expect(saved[0].containsKey('caption'), isFalse);
      expect(saved[1]['caption'], '');
      expect(saved[2].containsKey('attribution'), isFalse);
      expect(saved[3]['attribution'], '');
      expect(saved[4].containsKey('inlines'), isFalse);
      expect((saved[5]['inlines'] as List).single['marks'], isEmpty);
    });

    test('both supported versions can round-trip structured blocks', () {
      final blocks = <Map<String, Object?>>[
        {'id': 'p', 'type': 'paragraph', 'text': 'first'},
        {'id': 'h', 'type': 'heading', 'level': 4, 'text': 'title'},
        {
          'id': 'l',
          'type': 'list',
          'ordered': false,
          'items': [' one ', 'two'],
        },
        {'id': 'c', 'type': 'code', 'language': 'dart', 'code': ''},
      ];
      for (final version in [0, 1]) {
        final draft = document(blocks, version: version);
        expect(draft.version, version);
        expect(draft.toJsonBlocks(), blocks);
      }
    });

    test('input and serialized output cannot mutate the snapshot', () {
      final source = structuredArticle();
      final blocks = source['contentBlocks'] as List;
      final draft = StructuredArticleDraft.parse(version: 1, blocks: blocks);
      final original = jsonEncode(draft.blocks);
      (blocks.first as Map)['text'] = 'corrupt input';
      ((blocks.first as Map)['inlines'] as List).clear();
      final exported = draft.toJsonBlocks();
      exported.first['text'] = 'corrupt output';
      (exported.first['inlines'] as List).clear();
      expect(jsonEncode(draft.blocks), original);
      expect(() => draft.blocks.clear(), throwsUnsupportedError);
      expect(() => draft.blocks.first['text'] = 'x', throwsUnsupportedError);
      final runs = draft.blocks.first['inlines'] as List;
      expect(() => runs.clear(), throwsUnsupportedError);
      expect(() => (runs.first as Map)['text'] = 'x', throwsUnsupportedError);
      expect(
        () => ((runs.first as Map)['marks'] as List).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('block operations', () {
    test(
      'insert, move and remove preserve ids, ordering and untouched blocks',
      () {
        final original = fixture();
        final inserted = original.insert(1, paragraph('new', 'New text'));
        expect(inserted.blocks.map((b) => b['id']).toList(), [
          'heading',
          'new',
          'image-one',
          'paragraph',
          'quote',
          'list',
          'image-two',
          'code',
        ]);
        expect(original.blocks, hasLength(7));
        final moved = inserted.move('new', 7);
        expect(moved.blocks.last['id'], 'new');
        expect(moved.blocks.first, original.blocks.first);
        expect(moved.move('new', 0).blocks.first['id'], 'new');
        final removed = moved.remove('new');
        expect(removed.toJsonBlocks(), original.toJsonBlocks());
      },
    );

    test('insert accepts end position and copies caller-owned objects', () {
      final original = fixture();
      final nextBlock = paragraph('new', 'Added');
      final next = original.insert(original.blocks.length, nextBlock);
      nextBlock['text'] = 'mutated';
      expect(next.blocks.last['text'], 'Added');
      expect(original.blocks, hasLength(7));
    });

    test('invalid indexes, missing ids and id changes are rejected', () {
      final draft = fixture();
      expect(() => draft.insert(-1, paragraph('new', 'x')), throwsRangeError);
      expect(() => draft.insert(8, paragraph('new', 'x')), throwsRangeError);
      expect(() => draft.move('heading', -1), throwsRangeError);
      expect(() => draft.move('heading', 7), throwsRangeError);
      expect(() => draft.move('missing', 0), throwsArgumentError);
      expect(() => draft.remove('missing'), throwsArgumentError);
      expect(
        () => draft.replace('missing', paragraph('missing', 'x')),
        throwsArgumentError,
      );
      expect(
        () => draft.replace('paragraph', paragraph('another', 'x')),
        throwsArgumentError,
      );
      expect(draft.blocks, hasLength(7));
    });

    test('last block and duplicate ids cannot produce invalid snapshots', () {
      final one = document([paragraph('a', 'body')]);
      expect(() => one.remove('a'), throwsFormatException);
      expect(
        () => one.insert(1, paragraph('a', 'another')),
        throwsFormatException,
      );
      expect(one.toJsonBlocks(), [paragraph('a', 'body')]);
    });

    test(
      'changing image metadata preserves other blocks and absent fields',
      () {
        final draft = fixture();
        final image = draft.blocks[1];
        final changed = draft.replace('image-one', {
          ...image,
          'alt': 'Updated description',
          'caption': '',
        });
        expect(changed.blocks[1]['src'], '/media/one.png');
        expect(changed.blocks[1]['alt'], 'Updated description');
        expect(changed.blocks[1]['caption'], '');
        expect(changed.blocks[5], draft.blocks[5]);
        expect(draft.blocks[1]['alt'], 'First image alt');
      },
    );

    test(
      'invalid replacement is atomic and never modifies the prior value',
      () {
        final draft = fixture();
        final original = jsonEncode(draft.blocks);
        final image = draft.blocks[1];
        expect(
          () => draft.replace('image-one', {...image, 'src': 'javascript:bad'}),
          throwsFormatException,
        );
        expect(
          () => draft.replace('image-one', {...image, 'alt': null}),
          throwsFormatException,
        );
        expect(
          () => draft.replace('image-one', {...image, 'future': 1}),
          throwsFormatException,
        );
        expect(jsonEncode(draft.blocks), original);
      },
    );
  });

  group('text editing', () {
    test(
      'plain text changes one block without inventing inline formatting',
      () {
        final draft = fixture();
        final changed = draft.replacePlainText(
          'paragraph',
          'New **literal** text',
        );
        expect(changed.blocks[2]['text'], 'New **literal** text');
        expect(changed.blocks[2].containsKey('inlines'), isFalse);
        expect(changed.blocks.first, draft.blocks.first);
        expect(draft.blocks[2]['text'], 'literal **asterisks**');
      },
    );

    test('plain operation refuses to erase marks or edit non-text blocks', () {
      final draft = fixture();
      expect(
        () => draft.replacePlainText('heading', 'flattened'),
        throwsStateError,
      );
      expect(
        () => draft.replacePlainText('quote', 'flattened'),
        throwsStateError,
      );
      expect(
        () => draft.replacePlainText('image-one', 'x'),
        throwsArgumentError,
      );
      expect(() => draft.replacePlainText('list', 'x'), throwsArgumentError);
      expect(
        () => draft.replacePlainText('paragraph', ' '),
        throwsFormatException,
      );
    });

    test(
      'explicit runs update fallback while preserving supplied marks and links',
      () {
        final draft = fixture();
        final runs = <Map<String, Object?>>[
          {
            'text': 'New ',
            'marks': ['bold', 'italic'],
            'href': '/guide',
          },
          {
            'text': 'body',
            'marks': ['underline', 'code'],
          },
        ];
        final changed = draft.replaceTextRuns('heading', runs);
        expect(changed.blocks.first['text'], 'New body');
        expect(changed.blocks.first['inlines'], runs);
        expect(changed.blocks.first['level'], 2);
        expect(changed.blocks.first['id'], 'heading');
        expect(draft.blocks.first['text'], 'Bold代码');
        runs.first['text'] = 'later';
        expect(changed.blocks.first['text'], 'New body');
        expect((changed.blocks.first['inlines'] as List).first['text'], 'New ');
      },
    );

    test('can introduce explicit runs on a v1 plain block', () {
      final changed = fixture().replaceTextRuns('paragraph', [
        {
          'text': 'hello',
          'marks': ['bold'],
        },
        {'text': ' world'},
      ]);
      expect(changed.blocks[2]['text'], 'hello world');
      expect((changed.blocks[2]['inlines'] as List), hasLength(2));
    });

    test('v0 rejects inline edits and leaves source unchanged', () {
      final draft = document([paragraph('p', 'old')], version: 0);
      expect(
        () => draft.replaceTextRuns('p', [
          {'text': 'new'},
        ]),
        throwsFormatException,
      );
      expect(draft.blocks.single['text'], 'old');
    });

    test('empty, invalid or unsafe explicit runs cannot be saved', () {
      final draft = fixture();
      expect(() => draft.replaceTextRuns('heading', []), throwsFormatException);
      expect(
        () => draft.replaceTextRuns('heading', [
          {'text': ''},
        ]),
        throwsFormatException,
      );
      expect(
        () => draft.replaceTextRuns('heading', [
          {'text': 3},
        ]),
        throwsFormatException,
      );
      expect(
        () => draft.replaceTextRuns('heading', [
          {'text': 'x', 'href': 'javascript:x'},
        ]),
        throwsFormatException,
      );
      expect(
        () => draft.replaceTextRuns('heading', [
          {
            'text': 'x',
            'marks': ['bold', 'bold'],
          },
        ]),
        throwsFormatException,
      );
      expect(
        () => draft.replaceTextRuns('heading', [
          {
            'text': 'x',
            'marks': ['future'],
          },
        ]),
        throwsFormatException,
      );
      expect(
        () => draft.replaceTextRuns('image-one', [
          {'text': 'x'},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('list editing', () {
    test('one formatted item changes without flattening other items', () {
      final draft = fixture();
      final changed = draft.replaceListItemRuns('list', 1, [
        {
          'text': 'Changed ',
          'marks': ['italic'],
        },
        {'text': 'item', 'href': '/path'},
      ]);
      final originalList = draft.blocks[4];
      final list = changed.blocks[4];
      expect(list['items'], ['First item', 'Changed item']);
      expect(
        (list['itemInlines'] as List).first,
        (originalList['itemInlines'] as List).first,
      );
      expect((list['itemInlines'] as List).last, [
        {
          'text': 'Changed ',
          'marks': ['italic'],
        },
        {'text': 'item', 'href': '/path'},
      ]);
      expect(list['ordered'], isTrue);
      expect(originalList['items'], ['First item', ' second item ']);
    });

    test('plain list edits keep whitespace and other items', () {
      final draft = document([
        {
          'id': 'list',
          'type': 'list',
          'ordered': false,
          'items': ['first', 'second'],
        },
      ]);
      final changed = draft.replacePlainListItem('list', 1, '  another  ');
      expect(changed.blocks.single['items'], ['first', '  another  ']);
      expect(changed.blocks.single.containsKey('itemInlines'), isFalse);
      expect(draft.blocks.single['items'], ['first', 'second']);
    });

    test(
      'list editing rejects loss of formatting, bad indexes and wrong types',
      () {
        final formatted = fixture();
        expect(
          () => formatted.replacePlainListItem('list', 0, 'x'),
          throwsStateError,
        );
        expect(
          () => formatted.replaceListItemRuns('list', -1, [
            {'text': 'x'},
          ]),
          throwsRangeError,
        );
        expect(
          () => formatted.replaceListItemRuns('list', 2, [
            {'text': 'x'},
          ]),
          throwsRangeError,
        );
        expect(
          () => formatted.replaceListItemRuns('list', 0, []),
          throwsFormatException,
        );
        expect(
          () => formatted.replaceListItemRuns('heading', 0, [
            {'text': 'x'},
          ]),
          throwsArgumentError,
        );
        expect(
          () => formatted.replacePlainListItem('heading', 0, 'x'),
          throwsArgumentError,
        );
        final plain = document([
          {
            'id': 'l',
            'type': 'list',
            'ordered': true,
            'items': ['a'],
          },
        ]);
        expect(
          () => plain.replaceListItemRuns('l', 0, [
            {'text': 'x'},
          ]),
          throwsStateError,
        );
        expect(() => plain.replacePlainListItem('l', 1, 'x'), throwsRangeError);
        expect(
          () => plain.replacePlainListItem('l', 0, '  '),
          throwsFormatException,
        );
      },
    );
  });

  group('inline formatting operations', () {
    test('marks change one run and preserve links, neighbors and order', () {
      final original = fixture();
      final changed = original.setTextRunMark(
        'heading',
        1,
        'underline',
        enabled: false,
      );
      final runs = changed.blocks.first['inlines'] as List;
      final first = (original.blocks.first['inlines'] as List).first;
      expect(runs.first, first);
      expect(runs.last['text'], '代码');
      expect(runs.last['href'], 'https://external.example/path');
      expect(runs.last['marks'], ['code', 'bold', 'italic', 'strikethrough']);
      expect(
        (original.blocks.first['inlines'] as List).last['marks'],
        contains('underline'),
      );
      final restored = changed.setTextRunMark(
        'heading',
        1,
        'underline',
        enabled: true,
      );
      expect(
        (restored.blocks.first['inlines'] as List).last['marks'],
        contains('underline'),
      );
    });

    test('plain text is promoted to one explicit run only on v1', () {
      final original = fixture();
      final changed = original.setTextRunMark(
        'paragraph',
        0,
        'bold',
        enabled: true,
      );
      expect(changed.blocks[2]['text'], 'literal **asterisks**');
      expect(changed.blocks[2]['inlines'], [
        {
          'text': 'literal **asterisks**',
          'marks': ['bold'],
        },
      ]);
      expect(original.blocks[2].containsKey('inlines'), isFalse);
      final v0 = document([paragraph('p', 'plain')], version: 0);
      expect(
        () => v0.setTextRunMark('p', 0, 'bold', enabled: true),
        throwsFormatException,
      );
    });

    test('link editing preserves marks and removes only the chosen link', () {
      final original = fixture();
      final changed = original.setTextRunLink(
        'heading',
        0,
        'https://new.example/path',
      );
      final runs = changed.blocks.first['inlines'] as List;
      expect(runs.first['href'], 'https://new.example/path');
      expect(runs.first['marks'], [
        'bold',
        'italic',
        'underline',
        'strikethrough',
      ]);
      expect(runs.last['href'], 'https://external.example/path');
      final unlinked = changed.setTextRunLink('heading', 0, null);
      expect(
        (unlinked.blocks.first['inlines'] as List).first.containsKey('href'),
        isFalse,
      );
      expect(
        (original.blocks.first['inlines'] as List).first['href'],
        '/guide',
      );
    });

    test('invalid links, marks and indexes fail without altering source', () {
      final original = fixture();
      final before = jsonEncode(original.blocks);
      expect(
        () => original.setTextRunLink('heading', 0, 'javascript:bad'),
        throwsFormatException,
      );
      expect(
        () => original.setTextRunMark('heading', 0, 'future', enabled: true),
        throwsArgumentError,
      );
      expect(
        () => original.setTextRunMark('heading', 3, 'bold', enabled: true),
        throwsRangeError,
      );
      expect(
        () => original.setTextRunLink('image-one', 0, '/ok'),
        throwsArgumentError,
      );
      expect(jsonEncode(original.blocks), before);
    });

    test('list mark and link edit only the requested item and run', () {
      final original = fixture();
      final marked = original.setListRunMark(
        'list',
        1,
        0,
        'italic',
        enabled: true,
      );
      final linked = marked.setListRunLink('list', 1, 0, '/new');
      final runs = linked.blocks[4]['itemInlines'] as List;
      expect(runs.first, (original.blocks[4]['itemInlines'] as List).first);
      expect(runs.last, [
        {
          'text': ' second item ',
          'marks': ['underline', 'italic'],
          'href': '/new',
        },
      ]);
      expect(linked.blocks[4]['items'], ['First item', ' second item ']);
      final unlinked = linked.setListRunLink('list', 1, 0, null);
      expect(
        ((unlinked.blocks[4]['itemInlines'] as List).last as List).single
            .containsKey('href'),
        isFalse,
      );
    });

    test('plain list promotion preserves all text and validates version', () {
      final blocks = <Map<String, Object?>>[
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': [' first ', 'second'],
        },
      ];
      final source = document(blocks);
      final edited = source.setListRunLink('l', 1, 0, '/other');
      expect(edited.blocks.single['items'], [' first ', 'second']);
      expect(edited.blocks.single['itemInlines'], [
        [
          {'text': ' first '},
        ],
        [
          {'text': 'second', 'href': '/other'},
        ],
      ]);
      expect(source.toJsonBlocks(), blocks);
      expect(
        () => document(blocks, version: 0).setListRunLink('l', 0, 0, '/ok'),
        throwsFormatException,
      );
    });

    test('invalid list formatting and indexes do not touch any item', () {
      final original = fixture();
      final before = jsonEncode(original.blocks);
      expect(
        () => original.setListRunMark('list', -1, 0, 'bold', enabled: true),
        throwsRangeError,
      );
      expect(
        () => original.setListRunMark('list', 1, 3, 'bold', enabled: true),
        throwsRangeError,
      );
      expect(
        () => original.setListRunMark('list', 1, 0, 'future', enabled: true),
        throwsArgumentError,
      );
      expect(
        () => original.setListRunLink('list', 1, 0, '//evil.test'),
        throwsFormatException,
      );
      expect(
        () => original.setListRunLink('quote', 0, 0, '/x'),
        throwsArgumentError,
      );
      expect(jsonEncode(original.blocks), before);
    });
  });

  group('wire contract validation', () {
    test(
      'rejects unknown versions, malformed containers and empty documents',
      () {
        for (final version in [null, '1', -1, 2]) {
          expect(
            () => StructuredArticleDraft.parse(
              version: version,
              blocks: [paragraph('p', 'x')],
            ),
            throwsFormatException,
            reason: 'version $version',
          );
        }
        for (final blocks in [
          null,
          '[]',
          <Object>[],
          [null],
          [3],
        ]) {
          expect(
            () => StructuredArticleDraft.parse(version: 1, blocks: blocks),
            throwsFormatException,
            reason: 'blocks $blocks',
          );
        }
      },
    );

    test('rejects unknown block types and keys rather than dropping data', () {
      final invalid = <Map<String, Object?>>[
        {'id': 'a', 'type': 'video', 'src': '/v'},
        {'id': 'a', 'type': 'paragraph', 'text': 'x', 'newField': true},
        {
          'id': 'a',
          'type': 'heading',
          'text': 'x',
          'level': 2,
          'attribution': '',
        },
        {'id': 'a', 'type': 'quote', 'text': 'x', 'level': 2},
        {
          'id': 'a',
          'type': 'list',
          'ordered': true,
          'items': ['a'],
          'extra': 1,
        },
        {'id': 'a', 'type': 'image', 'src': '/a', 'alt': '', 'extra': 1},
        {'id': 'a', 'type': 'code', 'language': 'dart', 'code': '', 'extra': 1},
      ];
      for (final block in invalid) {
        expect(
          () => document([block]),
          throwsFormatException,
          reason: '$block',
        );
      }
    });

    test('requires a valid unique nonempty block identity', () {
      for (final id in [null, '', ' ', ' a', 'a ', 'x' * 101, 7]) {
        expect(
          () => document([
            {'id': id, 'type': 'paragraph', 'text': 'x'},
          ]),
          throwsFormatException,
          reason: '$id',
        );
      }
      expect(
        () => document([paragraph('a', 'one'), paragraph('a', 'two')]),
        throwsFormatException,
      );
      expect(
        document([paragraph('a', 'one'), paragraph('b', 'two')]).blocks,
        hasLength(2),
      );
    });

    test(
      'text, heading level and quotation attribution respect API bounds',
      () {
        for (final text in [null, '', '  ', ' x', 'x ', 'x' * 20001, 1]) {
          expect(
            () => document([
              {'id': 'a', 'type': 'paragraph', 'text': text},
            ]),
            throwsFormatException,
            reason: 'invalid text',
          );
        }
        expect(document([paragraph('a', 'x' * 20000)]).blocks, hasLength(1));
        for (final level in [null, 1, 5, 2.5, '2']) {
          expect(
            () => document([
              {'id': 'a', 'type': 'heading', 'text': 'x', 'level': level},
            ]),
            throwsFormatException,
            reason: 'level $level',
          );
        }
        for (final level in [2, 3, 4]) {
          expect(
            document([
              {'id': 'a', 'type': 'heading', 'text': 'x', 'level': level},
            ]).blocks,
            hasLength(1),
          );
        }
        expect(
          () => document([
            {'id': 'q', 'type': 'quote', 'text': 'x', 'attribution': null},
          ]),
          throwsFormatException,
        );
        expect(
          () => document([
            {'id': 'q', 'type': 'quote', 'text': 'x', 'attribution': 'a' * 301},
          ]),
          throwsFormatException,
        );
        expect(
          document([
            {'id': 'q', 'type': 'quote', 'text': 'x', 'attribution': 'a' * 300},
          ]).blocks,
          hasLength(1),
        );
      },
    );

    test('validates list count, item length, order and inline cardinality', () {
      final invalid = <Map<String, Object?>>[
        {
          'id': 'l',
          'type': 'list',
          'ordered': 'true',
          'items': ['x'],
        },
        {'id': 'l', 'type': 'list', 'ordered': true, 'items': []},
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': [''],
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': ['  '],
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': [1],
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': ['x' * 2001],
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': List.filled(101, 'x'),
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': ['x'],
          'itemInlines': [],
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': ['x'],
          'itemInlines': null,
        },
        {
          'id': 'l',
          'type': 'list',
          'ordered': true,
          'items': ['x'],
          'itemInlines': [
            [
              {'text': 'different'},
            ],
          ],
        },
      ];
      for (final block in invalid) {
        expect(
          () => document([block]),
          throwsFormatException,
          reason: '$block',
        );
      }
      final maximum = {
        'id': 'l',
        'type': 'list',
        'ordered': false,
        'items': List.filled(100, 'x' * 2000),
      };
      expect(document([maximum]).blocks, hasLength(1));
    });

    test(
      'image URL, alt and caption are bounded and do not allow credentials',
      () {
        final invalidSources = [
          '',
          ' ',
          '//evil.test/a',
          'javascript:alert(1)',
          'https://user:pass@example.test/a',
          '/a b',
          '/a\\b',
          'x' * 2049,
        ];
        for (final src in invalidSources) {
          expect(
            () => document([
              {'id': 'i', 'type': 'image', 'src': src, 'alt': ''},
            ]),
            throwsFormatException,
            reason: src,
          );
        }
        for (final src in [
          '/media/one',
          'https://example.test/image',
          'http://example.test/x',
        ]) {
          expect(
            document([
              {'id': 'i', 'type': 'image', 'src': src, 'alt': ''},
            ]).blocks.single['src'],
            src,
          );
        }
        expect(
          () => document([
            {'id': 'i', 'type': 'image', 'src': '/x', 'alt': null},
          ]),
          throwsFormatException,
        );
        expect(
          () => document([
            {'id': 'i', 'type': 'image', 'src': '/x', 'alt': 'x' * 1001},
          ]),
          throwsFormatException,
        );
        expect(
          () => document([
            {
              'id': 'i',
              'type': 'image',
              'src': '/x',
              'alt': '',
              'caption': null,
            },
          ]),
          throwsFormatException,
        );
        expect(
          () => document([
            {
              'id': 'i',
              'type': 'image',
              'src': '/x',
              'alt': '',
              'caption': 'x' * 1001,
            },
          ]),
          throwsFormatException,
        );
        expect(
          document([
            {
              'id': 'i',
              'type': 'image',
              'src': '/x',
              'alt': 'x' * 1000,
              'caption': '',
            },
          ]).blocks,
          hasLength(1),
        );
      },
    );

    test('code keeps whitespace but validates language and maximum size', () {
      for (final language in [null, '', ' ', ' dart', 'dart ', 'x' * 51]) {
        expect(
          () => document([
            {'id': 'c', 'type': 'code', 'language': language, 'code': ''},
          ]),
          throwsFormatException,
        );
      }
      expect(
        () => document([
          {'id': 'c', 'type': 'code', 'language': 'dart', 'code': null},
        ]),
        throwsFormatException,
      );
      expect(
        () => document([
          {'id': 'c', 'type': 'code', 'language': 'dart', 'code': 'x' * 50001},
        ]),
        throwsFormatException,
      );
      final text = ' \n${'x' * 49997}\n ';
      expect(
        document([
          {'id': 'c', 'type': 'code', 'language': 'dart', 'code': text},
        ]).blocks.single['code'],
        text,
      );
    });

    test('inline shape, exact fallback, links and marks are checked', () {
      final invalidRuns = <Object?>[
        null,
        [],
        [null],
        [
          {'text': ''},
        ],
        [
          {'text': 'x', 'extra': true},
        ],
        [
          {'text': 'wrong'},
        ],
        [
          {'text': 'x', 'marks': null},
        ],
        [
          {
            'text': 'x',
            'marks': ['bold', 'bold'],
          },
        ],
        [
          {
            'text': 'x',
            'marks': ['unknown'],
          },
        ],
        [
          {'text': 'x', 'href': null},
        ],
        [
          {'text': 'x', 'href': '//example.test'},
        ],
        [
          {'text': 'x', 'href': 'https://u@example.test/path'},
        ],
      ];
      for (final runs in invalidRuns) {
        expect(
          () => document([
            {'id': 'p', 'type': 'paragraph', 'text': 'x', 'inlines': runs},
          ]),
          throwsFormatException,
          reason: '$runs',
        );
      }
      final valid = {
        'id': 'p',
        'type': 'paragraph',
        'text': 'xy',
        'inlines': [
          {
            'text': 'x',
            'marks': ['bold', 'italic', 'underline', 'strikethrough', 'code'],
            'href': '/a',
          },
          {'text': 'y', 'marks': <String>[], 'href': 'https://example.test/b'},
        ],
      };
      expect(document([valid]).toJsonBlocks().single, valid);
      expect(() => document([valid], version: 0), throwsFormatException);
    });

    test('enforces whole-document size and block count', () {
      final valid = [for (var i = 0; i < 200; i++) paragraph('p$i', 'x')];
      expect(document(valid).blocks, hasLength(200));
      expect(
        () => document([...valid, paragraph('overflow', 'x')]),
        throwsFormatException,
      );
      final oversized = [
        for (var i = 0; i < 21; i++)
          {
            'id': 'c$i',
            'type': 'code',
            'language': 'plain',
            'code': 'x' * 50000,
          },
      ];
      expect(() => document(oversized), throwsFormatException);
    });

    test('rejects non JSON values and cyclic input', () {
      final cyclic = <String, Object?>{
        'id': 'p',
        'type': 'paragraph',
        'text': 'x',
      };
      cyclic['unknown'] = cyclic;
      expect(() => document([cyclic]), throwsFormatException);
      expect(
        () => document([
          {'id': 'p', 'type': 'paragraph', 'text': 'x', 'extra': Object()},
        ]),
        throwsFormatException,
      );
    });
  });
}
