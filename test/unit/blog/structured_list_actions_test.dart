import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_list_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: 1,
    blocks: article['contentBlocks'],
  );
}

StructuredArticleDraft _plain(List<String> items, {int version = 0}) =>
    StructuredArticleDraft.parse(
      version: version,
      blocks: [
        {'id': 'list', 'type': 'list', 'ordered': false, 'items': items},
      ],
    );

void main() {
  test(
    'reorder preserves matching inline runs, whitespace, and other blocks',
    () {
      final body = _body();
      final before = body.blocks[4];
      final changed = StructuredListMove(
        source: body,
        blockId: 'list',
        index: 0,
        destination: 1,
      ).apply(body);
      final after = changed.blocks[4];
      expect(after['items'], [' second item ', 'First item']);
      expect(
        after['itemInlines'],
        (before['itemInlines'] as List).reversed.toList(),
      );
      expect(changed.blocks[0], body.blocks[0]);
      expect(changed.blocks[1], body.blocks[1]);
      expect(changed.blocks[5], body.blocks[5]);
      expect(body.blocks[4], before);
    },
  );

  test(
    'insert in a formatted list uses a separate literal unformatted run',
    () {
      final body = _body();
      final before = body.blocks[4];
      final changed = StructuredListInsert(
        source: body,
        blockId: 'list',
        index: 1,
        text: '  new 👋  ',
      ).apply(body);
      final block = changed.blocks[4];
      expect(block['items'], ['First item', '  new 👋  ', ' second item ']);
      final runs = block['itemInlines'] as List;
      expect(runs[0], (before['itemInlines'] as List)[0]);
      expect(runs[1], [
        {'text': '  new 👋  '},
      ]);
      expect(runs[2], (before['itemInlines'] as List)[1]);
    },
  );

  test('plain v0 and v1 lists never silently gain inline data', () {
    for (final version in [0, 1]) {
      final body = _plain(['one', 'two'], version: version);
      final inserted = StructuredListInsert(
        source: body,
        blockId: 'list',
        index: 0,
        text: 'zero',
      ).apply(body);
      expect(inserted.blocks.single.containsKey('itemInlines'), isFalse);
      final moved = StructuredListMove(
        source: inserted,
        blockId: 'list',
        index: 0,
        destination: 2,
      ).apply(inserted);
      final removed = StructuredListRemove(
        source: moved,
        blockId: 'list',
        index: 1,
      ).apply(moved);
      expect(removed.blocks.single['items'], ['one', 'zero']);
      expect(removed.blocks.single.containsKey('itemInlines'), isFalse);
    }
  });

  test('deleting item removes only corresponding formatted runs', () {
    final body = _body();
    final next = StructuredListRemove(
      source: body,
      blockId: 'list',
      index: 0,
    ).apply(body);
    expect(next.blocks[4]['items'], [' second item ']);
    expect(next.blocks[4]['itemInlines'], [
      (body.blocks[4]['itemInlines'] as List)[1],
    ]);
    expect(
      () => StructuredListRemove(
        source: next,
        blockId: 'list',
        index: 0,
      ).apply(next),
      throwsStateError,
    );
    expect(body.blocks[4]['items'], ['First item', ' second item ']);
  });

  test(
    'invalid bounds, invalid UTF-16 and schema limits do not change source',
    () {
      final body = _plain(['x']);
      expect(
        () => StructuredListInsert(
          source: body,
          blockId: 'list',
          index: -1,
          text: 'x',
        ).apply(body),
        throwsRangeError,
      );
      expect(
        () => StructuredListInsert(
          source: body,
          blockId: 'list',
          index: 1,
          text: '  ',
        ).apply(body),
        throwsFormatException,
      );
      expect(
        () => StructuredListInsert(
          source: body,
          blockId: 'list',
          index: 1,
          text: String.fromCharCode(0xd800),
        ).apply(body),
        throwsFormatException,
      );
      expect(
        () => StructuredListMove(
          source: body,
          blockId: 'list',
          index: 0,
          destination: 1,
        ).apply(body),
        throwsRangeError,
      );
      final full = _plain(List.generate(100, (index) => '$index'));
      expect(
        () => StructuredListInsert(
          source: full,
          blockId: 'list',
          index: 100,
          text: 'extra',
        ).apply(full),
        throwsFormatException,
      );
      expect(body.blocks.single['items'], ['x']);
    },
  );

  test('item identity is bound to an exact body and list kind', () {
    final body = _body();
    final equal = _body();
    final action = StructuredListMove(
      source: body,
      blockId: 'list',
      index: 0,
      destination: 1,
    );
    expect(() => action.apply(equal), throwsStateError);
    expect(
      () => StructuredListRemove(
        source: body,
        blockId: 'quote',
        index: 0,
      ).apply(body),
      throwsStateError,
    );
    expect(
      () => StructuredListRemove(
        source: body,
        blockId: 'missing',
        index: 0,
      ).apply(body),
      throwsStateError,
    );
  });
}
