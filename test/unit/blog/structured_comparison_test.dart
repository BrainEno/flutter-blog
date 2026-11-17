import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
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
  test('map key order does not change a body; version is compared', () {
    final a = doc([p('a', 'x')], version: 0);
    final b = doc([
      {'text': 'x', 'type': 'paragraph', 'id': 'a'},
    ]);
    final result = StructuredDocumentComparison.between(a, b);
    expect(result.versionChanged, isTrue);
    expect(result.hasChanges, isTrue);
    expect(result.unchangedCount, 1);
    expect(result.entries.single.fields, isEmpty);
  });
  test('insertions and deletions do not cause false moves', () {
    final a = doc([p('a', 'A'), p('b', 'B'), p('c', 'C')]);
    final b = doc([p('new', 'N'), p('a', 'A'), p('c', 'C')]);
    final result = StructuredDocumentComparison.between(a, b);
    expect(result.addedCount, 1);
    expect(result.removedCount, 1);
    expect(result.movedCount, 0);
    expect(result.entries.map((e) => e.id), ['new', 'a', 'c', 'b']);
    expect(result.entries.last.beforeIndex, 1);
    expect(result.entries.last.afterIndex, isNull);
  });
  test('reordering is deterministic and a moved block may also change', () {
    final a = doc([p('a', 'A'), p('b', 'B'), p('c', 'C')]);
    final b = doc([p('b', 'B'), p('c', 'C'), p('a', 'changed')]);
    final result = StructuredDocumentComparison.between(a, b);
    expect(result.movedCount, 1);
    expect(result.modifiedCount, 1);
    final entry = result.entries.singleWhere((e) => e.id == 'a');
    expect(entry.moved, isTrue);
    expect(entry.modified, isTrue);
    expect(entry.fields.single.before, 'A');
    expect(entry.fields.single.after, 'changed');
  });
  test('optional absence differs from present empty value', () {
    final a = doc([
      {'id': 'i', 'type': 'image', 'src': '/img', 'alt': ''},
    ]);
    final b = doc([
      {'id': 'i', 'type': 'image', 'src': '/img', 'alt': '', 'caption': ''},
    ]);
    final field = StructuredDocumentComparison.between(
      a,
      b,
    ).entries.single.fields.single;
    expect(field.name, 'caption');
    expect(field.beforePresent, isFalse);
    expect(field.afterPresent, isTrue);
    expect(field.after, '');
  });
  test(
    'nested inline data is compared without flattening or sorting arrays',
    () {
      final a = doc([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'abc',
          'inlines': [
            {
              'text': 'abc',
              'marks': ['bold', 'italic'],
            },
          ],
        },
      ]);
      final b = doc([
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'abc',
          'inlines': [
            {
              'marks': ['italic', 'bold'],
              'text': 'abc',
            },
          ],
        },
      ]);
      final result = StructuredDocumentComparison.between(a, b);
      expect(result.entries.single.fields.single.name, 'inlines');
      expect(result.modifiedCount, 1);
      expect(a.blocks.single['text'], b.blocks.single['text']);
      expect(() => result.entries.clear(), throwsUnsupportedError);
      expect(
        () => result.entries.single.fields.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('type changes compare exact fields and retain both types', () {
    final a = doc([p('a', 'text')]);
    final b = doc([
      {'id': 'a', 'type': 'heading', 'text': 'text', 'level': 2},
    ]);
    final change = StructuredDocumentComparison.between(a, b).entries.single;
    expect(change.beforeType, 'paragraph');
    expect(change.afterType, 'heading');
    expect(change.fields.map((f) => f.name), ['type', 'level']);
  });
  test('maximum-size reverse ordering is bounded and deterministic', () {
    final before = doc([for (var i = 0; i < 200; i++) p('id$i', '$i')]);
    final after = doc(before.toJsonBlocks().reversed.toList());
    final one = StructuredDocumentComparison.between(before, after);
    final two = StructuredDocumentComparison.between(before, after);
    expect(one.movedCount, 199);
    expect(
      one.entries.where((e) => e.moved).map((e) => e.id),
      two.entries.where((e) => e.moved).map((e) => e.id),
    );
  });
}
