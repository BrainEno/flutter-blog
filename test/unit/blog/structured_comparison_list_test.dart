import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison_list.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredArticleDraft list(List<String> items, {List<Object?>? runs}) =>
    StructuredArticleDraft.parse(
      version: 1,
      blocks: [
        {
          'id': 'list',
          'type': 'list',
          'ordered': false,
          'items': items,
          if (runs != null) 'itemInlines': runs,
        },
      ],
    );

void main() {
  test(
    'compares ordinals, preserving absent item and optional inline arrays',
    () {
      final before = list(['same', 'same']);
      final after = list(
        ['same', 'new', 'same'],
        runs: [
          [
            {'text': 'same', 'marks': <String>[]},
          ],
          [
            {'text': 'new', 'marks': <String>[]},
          ],
          [
            {'text': 'same', 'marks': <String>[]},
          ],
        ],
      );
      final rows = compareStructuredListItems(before, after, 'list')!;
      expect(rows.length, 3);
      expect(rows[0].fields.single.name, 'inlines');
      expect(rows[0].fields.single.beforePresent, isFalse);
      expect(rows[1].fields.map((f) => f.name), ['text', 'inlines']);
      expect(rows[2].fields.first.beforePresent, isFalse);
      expect(rows[2].fields.first.after, 'same');
      expect(() => rows.clear(), throwsUnsupportedError);
      expect(() => rows[1].fields.clear(), throwsUnsupportedError);
    },
  );
  test('does not match unrelated or replaced block types', () {
    final before = list(['text']);
    final after = StructuredArticleDraft.parse(
      version: 1,
      blocks: [
        {'id': 'list', 'type': 'paragraph', 'text': 'text'},
      ],
    );
    expect(compareStructuredListItems(before, after, 'list'), isNull);
    expect(compareStructuredListItems(before, before, 'missing'), isNull);
    expect(
      compareStructuredListItems(before, before, 'list')!.single.changed,
      isFalse,
    );
  });
}
