import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_history_patch.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredArticleDraft doc(
  List<Map<String, Object?>> blocks, {
  int version = 1,
}) => StructuredArticleDraft.parse(version: version, blocks: blocks);
Map<String, Object?> p(String id, String text) => {
  'id': id,
  'type': 'paragraph',
  'text': text,
};

void main() {
  test(
    'replaces only selected contents, preserving current order and all other blocks',
    () {
      final old = doc([
        p('p', 'old'),
        {
          'id': 'img',
          'type': 'image',
          'src': '/photo',
          'alt': 'old alt',
          'caption': '',
        },
        {
          'id': 'list',
          'type': 'list',
          'ordered': true,
          'items': ['a', 'b'],
        },
      ]);
      final current = doc([
        {
          'id': 'list',
          'type': 'list',
          'ordered': false,
          'items': ['b', 'a'],
        },
        p('p', 'new'),
        {'id': 'img', 'type': 'image', 'src': '/new-photo', 'alt': 'new alt'},
        p('added', 'still here'),
      ]);
      final ids = {'p', 'img'};
      final plan = StructuredHistoryPatch.prepare(
        current: current,
        source: old,
        blockIds: ids,
      );
      ids.clear();
      expect(plan.blockIds, {'p', 'img'});
      expect(() => plan.blockIds.clear(), throwsUnsupportedError);
      expect(plan.result.blocks.map((block) => block['id']), [
        'list',
        'p',
        'img',
        'added',
      ]);
      expect(plan.result.blocks[0], current.blocks[0]);
      expect(plan.result.blocks[1], old.blocks[0]);
      expect(plan.result.blocks[2], old.blocks[1]);
      expect(plan.result.blocks[3], current.blocks[3]);
      expect(current.blocks[1]['text'], 'new');
      expect(old.blocks[0]['text'], 'old');
    },
  );
  test(
    'rejects absent, identical and empty selection without partial result',
    () {
      final old = doc([p('p', 'old'), p('unchanged', 'same')]);
      final current = doc([
        p('p', 'new'),
        p('unchanged', 'same'),
        p('extra', 'new'),
      ]);
      for (final ids in [
        <String>{},
        {'p', 'extra'},
        {'p', 'missing'},
        {'p', 'unchanged'},
      ]) {
        expect(
          () => StructuredHistoryPatch.prepare(
            current: current,
            source: old,
            blockIds: ids,
          ),
          throwsFormatException,
        );
      }
      expect(current.blocks[0]['text'], 'new');
    },
  );
  test(
    'combined size limit rejects the entire batch without changing either body',
    () {
      Map<String, Object?> code(int index, bool large) => {
        'id': 'b$index',
        'type': 'code',
        'language': 'plain',
        'code': large ? List.filled(20000, 'x').join() : '',
      };
      final current = doc([for (var i = 0; i < 60; i++) code(i, i < 30)]);
      final source = doc([for (var i = 0; i < 60; i++) code(i, i >= 30)]);
      final ids = {for (var i = 30; i < 60; i++) 'b$i'};
      expect(
        () => StructuredHistoryPatch.prepare(
          current: current,
          source: source,
          blockIds: ids,
        ),
        throwsFormatException,
      );
      expect(current.blocks[0]['code'], isNotEmpty);
      expect(current.blocks.last['code'], isEmpty);
      expect(source.blocks.first['code'], isEmpty);
      expect(source.blocks.last['code'], isNotEmpty);
    },
  );

  test('mixed version rejects unsupported inline fields atomically', () {
    final current = doc([p('p', 'old'), p('other', 'safe')], version: 0);
    final source = doc([
      {
        'id': 'p',
        'type': 'paragraph',
        'text': 'new',
        'inlines': [
          {
            'text': 'new',
            'marks': ['bold'],
          },
        ],
      },
      p('other', 'safe'),
    ]);
    expect(
      () => StructuredHistoryPatch.prepare(
        current: current,
        source: source,
        blockIds: {'p'},
      ),
      throwsFormatException,
    );
    expect(current.version, 0);
    expect(current.blocks[0]['text'], 'old');
  });
}
