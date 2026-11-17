import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_recovery_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

StructuredBlockChange _change(
  StructuredRecoveryComparison comparison,
  String id,
) => comparison.changes.singleWhere((change) => change.id == id);

void main() {
  test('reports added removed moved and modified blocks without pairing IDs', () {
    final base = _body();
    final heading = Map<String, Object?>.of(base.blocks.first)..['level'] = 3;
    var local = base.replace('heading', heading);
    local = local.move('image-two', 1);
    local = local.remove('quote');
    local = local.insert(3, {
      'id': 'new-paragraph',
      'type': 'paragraph',
      'text': 'A strictly local addition',
    });

    final comparison = StructuredRecoveryComparison.compare(
      base: base,
      local: local,
    );

    expect(comparison.baseVersion, 1);
    expect(comparison.localVersion, 1);
    expect(comparison.addedCount, 1);
    expect(comparison.removedCount, 1);
    expect(comparison.movedCount, 4);
    expect(comparison.modifiedCount, 1);

    final added = _change(comparison, 'new-paragraph');
    expect(added.kinds, {StructuredBlockChangeKind.added});
    expect(added.base, isNull);
    expect(added.local!.position, 3);

    final removed = _change(comparison, 'quote');
    expect(removed.kinds, {StructuredBlockChangeKind.removed});
    expect(removed.base!.position, 3);
    expect(removed.local, isNull);

    final moved = _change(comparison, 'image-two');
    expect(moved.kinds, {StructuredBlockChangeKind.moved});
    expect(moved.base!.position, 5);
    expect(moved.local!.position, 1);

    final modified = _change(comparison, 'heading');
    expect(modified.kinds, {StructuredBlockChangeKind.modified});
    expect(modified.fields, hasLength(1));
    expect(modified.fields.single.field, 'level');
    expect(modified.fields.single.before, 2);
    expect(modified.fields.single.after, 3);
  });

  test('keeps missing optional fields distinct from an explicit value', () {
    final base = _body();
    final image = Map<String, Object?>.of(base.blocks[1])
      ..remove('caption')
      ..['alt'] = 'Changed local description';
    final local = base.replace('image-one', image);

    final change = _change(
      StructuredRecoveryComparison.compare(base: base, local: local),
      'image-one',
    );
    final caption = change.fields.singleWhere((field) => field.field == 'caption');
    final alt = change.fields.singleWhere((field) => field.field == 'alt');

    expect(caption.hadBefore, isTrue);
    expect(caption.before, 'First caption');
    expect(caption.hasAfter, isFalse);
    expect(caption.after, isNull);
    expect(alt.hadBefore, isTrue);
    expect(alt.hasAfter, isTrue);
    expect(alt.before, 'First image alt');
    expect(alt.after, 'Changed local description');
  });

  test('keeps nested inline runs in defensive read-only snapshots', () {
    final base = _body();
    final heading = Map<String, Object?>.of(base.blocks.first)
      ..['inlines'] = [
        {
          'text': 'Replacement',
          'marks': ['bold'],
          'href': '/new-link',
        },
      ]
      ..['text'] = 'Replacement';
    final local = base.replace('heading', heading);

    final change = _change(
      StructuredRecoveryComparison.compare(base: base, local: local),
      'heading',
    );
    final inlines = change.fields.singleWhere(
      (field) => field.field == 'inlines',
    );
    final runs = inlines.after! as List<Object?>;
    final run = runs.single as Map<String, Object?>;
    final marks = run['marks']! as List<Object?>;

    expect(run['href'], '/new-link');
    expect(marks, ['bold']);
    expect(() => run['href'] = '/mutated', throwsUnsupportedError);
    expect(() => marks.add('italic'), throwsUnsupportedError);
    expect(base.blocks.first['inlines'], isNot(runs));
  });

  test('has no changes for the exact same immutable body', () {
    final body = _body();
    final comparison = StructuredRecoveryComparison.compare(
      base: body,
      local: body,
    );

    expect(comparison.hasChanges, isFalse);
    expect(comparison.changes, isEmpty);
    expect(comparison.unchangedBlockCount, body.blocks.length);
  });

  test('refuses to reinterpret different document versions', () {
    final legacy = StructuredArticleDraft.parse(
      version: 0,
      blocks: [
        {'id': 'legacy', 'type': 'paragraph', 'text': 'Older document'},
      ],
    );

    expect(
      () => StructuredRecoveryComparison.compare(base: _body(), local: legacy),
      throwsFormatException,
    );
  });
}
