import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_block_insertion.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredArticleDraft _body({int version = 1}) => StructuredArticleDraft.parse(
  version: version,
  blocks: [
    {'id': 'a', 'type': 'paragraph', 'text': 'original'},
    {'id': 'b', 'type': 'image', 'src': '/image', 'alt': 'old', 'caption': ''},
  ],
);

void main() {
  test(
    'all six types insert after anchor without changing existing blocks',
    () {
      final examples = <StructuredNewBlockKind, Map<String, Object?>>{
        StructuredNewBlockKind.paragraph: {
          'id': 'new',
          'type': 'paragraph',
          'text': 'value',
        },
        StructuredNewBlockKind.heading: {
          'id': 'new',
          'type': 'heading',
          'text': 'value',
          'level': 4,
        },
        StructuredNewBlockKind.quote: {
          'id': 'new',
          'type': 'quote',
          'text': 'value',
          'attribution': '',
        },
        StructuredNewBlockKind.list: {
          'id': 'new',
          'type': 'list',
          'ordered': true,
          'items': ['value'],
        },
        StructuredNewBlockKind.image: {
          'id': 'new',
          'type': 'image',
          'src': '/new',
          'alt': 'detail',
          'caption': '',
        },
        StructuredNewBlockKind.code: {
          'id': 'new',
          'type': 'code',
          'language': 'value',
          'code': 'detail',
        },
      };
      for (final version in [0, 1]) {
        for (final entry in examples.entries) {
          final body = _body(version: version);
          final result = StructuredBlockInsertion(
            source: body,
            afterBlockId: 'a',
            newBlockId: 'new',
            kind: entry.key,
            text: entry.key == StructuredNewBlockKind.image ? '/new' : 'value',
            secondary: 'detail',
            optionalPresent: true,
            headingLevel: 4,
            ordered: true,
          ).apply(body);
          expect(result.blocks[1], entry.value);
          expect(result.blocks[0], body.blocks[0]);
          expect(result.blocks[2], body.blocks[1]);
          expect(result.version, version);
        }
      }
    },
  );

  test('optional absence differs from present empty', () {
    final body = _body();
    final result = StructuredBlockInsertion(
      source: body,
      afterBlockId: 'b',
      newBlockId: 'new',
      kind: StructuredNewBlockKind.quote,
      text: 'quote',
    ).apply(body);
    expect(result.blocks.last.containsKey('attribution'), isFalse);
    expect(result.blocks[1]['caption'], '');
  });

  test(
    'requires exact source, existing anchor, unique ID and valid schema',
    () {
      final body = _body();
      final command = StructuredBlockInsertion(
        source: body,
        afterBlockId: 'a',
        newBlockId: 'new',
        kind: StructuredNewBlockKind.paragraph,
        text: 'new',
      );
      expect(() => command.apply(_body()), throwsStateError);
      expect(
        () => StructuredBlockInsertion(
          source: body,
          afterBlockId: 'missing',
          newBlockId: 'new',
          kind: StructuredNewBlockKind.paragraph,
          text: 'new',
        ).apply(body),
        throwsStateError,
      );
      expect(
        () => StructuredBlockInsertion(
          source: body,
          afterBlockId: 'a',
          newBlockId: 'b',
          kind: StructuredNewBlockKind.paragraph,
          text: 'new',
        ).apply(body),
        throwsFormatException,
      );
      expect(
        () => StructuredBlockInsertion(
          source: body,
          afterBlockId: 'a',
          newBlockId: 'new',
          kind: StructuredNewBlockKind.image,
          text: 'javascript:alert(1)',
        ).apply(body),
        throwsFormatException,
      );
      expect(
        () => StructuredBlockInsertion(
          source: body,
          afterBlockId: 'a',
          newBlockId: 'new',
          kind: StructuredNewBlockKind.heading,
          text: 'x',
          headingLevel: 1,
        ).apply(body),
        throwsFormatException,
      );
      expect(
        () => StructuredBlockInsertion(
          source: body,
          afterBlockId: 'a',
          newBlockId: 'new',
          kind: StructuredNewBlockKind.paragraph,
          text: String.fromCharCode(0xdfff),
        ).apply(body),
        throwsFormatException,
      );
      expect(body.blocks, hasLength(2));
    },
  );

  test(
    '200 block ceiling rejects insert rather than dropping existing blocks',
    () {
      final full = StructuredArticleDraft.parse(
        version: 1,
        blocks: List.generate(
          200,
          (i) => {'id': '$i', 'type': 'paragraph', 'text': 'x'},
        ),
      );
      expect(
        () => StructuredBlockInsertion(
          source: full,
          afterBlockId: '0',
          newBlockId: 'new',
          kind: StructuredNewBlockKind.paragraph,
          text: 'x',
        ).apply(full),
        throwsFormatException,
      );
      expect(full.blocks.length, 200);
    },
  );
}
