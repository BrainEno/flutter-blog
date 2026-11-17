import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_body_history.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredArticleDraft body(String text) => StructuredArticleDraft.parse(
  version: 1,
  blocks: [
    {'id': 'p', 'type': 'paragraph', 'text': text},
  ],
);

void main() {
  test('undo, redo and branching require exact view and body', () {
    final history = StructuredBodyHistory();
    final a = body('a');
    final b = body('b');
    final c = body('c');
    history.initialize(a);
    expect(history.record(a, b), isTrue);
    expect(history.record(b, c), isTrue);
    final atC = history.capture(c)!;
    expect(atC.entries.length, 3);
    expect(atC.canUndo, isTrue);
    expect(atC.canRedo, isFalse);
    expect(
      history.select(
        current: c,
        generation: atC.generation,
        entryId: atC.entries[1].id,
      ),
      same(b),
    );
    expect(
      history.select(
        current: c,
        generation: atC.generation,
        entryId: atC.entries.first.id,
      ),
      isNull,
    );
    final atB = history.capture(b)!;
    expect(atB.canUndo, isTrue);
    expect(atB.canRedo, isTrue);
    expect(history.record(b, body('b')), isFalse);
    expect(history.capture(b)!.canRedo, isTrue);
    final d = body('d');
    expect(history.record(b, d), isTrue);
    final atD = history.capture(d)!;
    expect(atD.canRedo, isFalse);
    expect(atD.entries.map((e) => e.body.blocks.single['text']), [
      'a',
      'b',
      'd',
    ]);
    expect(atD.entries.last.id, greaterThan(atC.entries.last.id));
    expect(history.record(c, body('stale')), isNull);
    expect(() => atD.entries.clear(), throwsUnsupportedError);
  });
  test('both entry count and encoded size bounds evict old snapshots', () {
    final history = StructuredBodyHistory(maxEntries: 3, maxUnits: 2000000);
    var current = body('0');
    history.initialize(current);
    for (var i = 1; i < 8; i++) {
      final next = body('$i');
      expect(history.record(current, next), isTrue);
      current = next;
    }
    final view = history.capture(current)!;
    expect(view.entries.length, 3);
    expect(view.truncated, isTrue);
    expect(view.entries.map((entry) => entry.body.blocks.single['text']), [
      '5',
      '6',
      '7',
    ]);
    final small = StructuredBodyHistory(maxUnits: 50);
    final first = body('x');
    final second = body('y');
    small.initialize(first);
    expect(small.record(first, second), isTrue);
    expect(small.capture(second)!.entries.length, 1);
    expect(small.capture(second)!.truncated, isTrue);
  });
  test('clear invalidates captured IDs and generations without reuse', () {
    final h = StructuredBodyHistory();
    final a = body('a');
    final b = body('b');
    h.initialize(a);
    h.record(a, b);
    final old = h.capture(b)!;
    h.clear();
    expect(h.capture(b), isNull);
    h.initialize(b);
    final next = h.capture(b)!;
    expect(next.current.id, greaterThan(old.current.id));
    expect(
      h.select(
        current: b,
        generation: old.generation,
        entryId: old.entries.first.id,
      ),
      isNull,
    );
    expect(() => StructuredBodyHistory(maxEntries: 1), throwsArgumentError);
    expect(() => StructuredBodyHistory(maxUnits: 0), throwsArgumentError);
  });
}
