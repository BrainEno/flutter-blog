import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';

/// Three immutable, already validated documents belonging to one local
/// session. [remote] is only the read taken when that session opened: it is
/// not a live fetch, authorization, version token, or proof of server state.
/// Metadata is intentionally not represented by this comparison.
final class StructuredComparisonCapture {
  const StructuredComparisonCapture({
    required this.base,
    required this.local,
    required this.remote,
    required this.remoteStatus,
  });
  final StructuredArticleDraft base;
  final StructuredArticleDraft local;
  final StructuredArticleDraft? remote;
  final StructuredEditionReadStatus? remoteStatus;
}

/// One changed block field. Presence is distinct from a present null or empty
/// value; neither text normalization nor rendered Markdown is used to compare.
final class StructuredFieldChange {
  const StructuredFieldChange({
    required this.name,
    required this.beforePresent,
    required this.before,
    required this.afterPresent,
    required this.after,
  });
  final String name;
  final bool beforePresent;
  final Object? before;
  final bool afterPresent;
  final Object? after;
}

/// One stable block ID across two validated documents. An entry may be both
/// moved and modified. Positions are zero-based and null on the absent side.
final class StructuredBlockChange {
  const StructuredBlockChange({
    required this.id,
    required this.beforeIndex,
    required this.afterIndex,
    required this.beforeType,
    required this.afterType,
    required this.moved,
    required this.fields,
  });
  final String id;
  final int? beforeIndex;
  final int? afterIndex;
  final String? beforeType;
  final String? afterType;
  final bool moved;
  final List<StructuredFieldChange> fields;

  bool get added => beforeIndex == null;
  bool get removed => afterIndex == null;
  bool get modified => !added && !removed && fields.isNotEmpty;
  bool get changed => added || removed || moved || modified;
}

/// Exact structural comparison of body snapshots, not a merge or text diff.
/// Map key order is ignored; array order, field presence, Unicode code units,
/// marks and link strings are significant. The result keeps references to the
/// input snapshots and must be discarded on account invalidation.
final class StructuredDocumentComparison {
  StructuredDocumentComparison._({
    required this.before,
    required this.after,
    required this.entries,
  });

  factory StructuredDocumentComparison.between(
    StructuredArticleDraft before,
    StructuredArticleDraft after,
  ) {
    final beforeById = <String, int>{
      for (var i = 0; i < before.blocks.length; i++)
        before.blocks[i]['id'] as String: i,
    };
    final afterById = <String, int>{
      for (var i = 0; i < after.blocks.length; i++)
        after.blocks[i]['id'] as String: i,
    };
    // Detect order changes among shared blocks rather than reporting every
    // block as moved when another was merely inserted or deleted. The bounded
    // LCS uses at most 201*201 cells because validation caps each document at
    // 200 blocks. A deterministic tie rule makes repeated views stable.
    final oldIds = [for (final block in before.blocks) block['id'] as String];
    final newIds = [for (final block in after.blocks) block['id'] as String];
    final stable = _longestCommonSubsequence(oldIds, newIds);
    final entries = <StructuredBlockChange>[];
    for (var index = 0; index < after.blocks.length; index++) {
      final next = after.blocks[index];
      final id = next['id'] as String;
      final oldIndex = beforeById[id];
      final previous = oldIndex == null ? null : before.blocks[oldIndex];
      final fields = _fields(previous, next);
      entries.add(
        StructuredBlockChange(
          id: id,
          beforeIndex: oldIndex,
          afterIndex: index,
          beforeType: previous?['type'] as String?,
          afterType: next['type'] as String,
          moved: oldIndex != null && !stable.contains(id),
          fields: fields,
        ),
      );
    }
    // Removed entries follow the after-document order. Their old positions
    // remain available so the presentation can identify their original place.
    for (var index = 0; index < before.blocks.length; index++) {
      final previous = before.blocks[index];
      final id = previous['id'] as String;
      if (afterById.containsKey(id)) continue;
      entries.add(
        StructuredBlockChange(
          id: id,
          beforeIndex: index,
          afterIndex: null,
          beforeType: previous['type'] as String,
          afterType: null,
          moved: false,
          fields: _fields(previous, null),
        ),
      );
    }
    return StructuredDocumentComparison._(
      before: before,
      after: after,
      entries: List.unmodifiable(entries),
    );
  }

  final StructuredArticleDraft before;
  final StructuredArticleDraft after;
  final List<StructuredBlockChange> entries;

  bool get versionChanged => before.version != after.version;
  int get addedCount => entries.where((entry) => entry.added).length;
  int get removedCount => entries.where((entry) => entry.removed).length;
  int get movedCount => entries.where((entry) => entry.moved).length;
  int get modifiedCount => entries.where((entry) => entry.modified).length;
  int get unchangedCount => entries.where((entry) => !entry.changed).length;
  bool get hasChanges =>
      versionChanged || entries.any((entry) => entry.changed);
}

Set<String> _longestCommonSubsequence(List<String> before, List<String> after) {
  final rows = List.generate(
    before.length + 1,
    (_) => List<int>.filled(after.length + 1, 0),
  );
  for (var i = before.length - 1; i >= 0; i--) {
    for (var j = after.length - 1; j >= 0; j--) {
      rows[i][j] = before[i] == after[j]
          ? rows[i + 1][j + 1] + 1
          : (rows[i + 1][j] >= rows[i][j + 1]
                ? rows[i + 1][j]
                : rows[i][j + 1]);
    }
  }
  final stable = <String>{};
  var i = 0;
  var j = 0;
  while (i < before.length && j < after.length) {
    if (before[i] == after[j]) {
      stable.add(before[i]);
      i++;
      j++;
    } else if (rows[i + 1][j] >= rows[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return stable;
}

List<StructuredFieldChange> _fields(
  Map<String, Object?>? before,
  Map<String, Object?>? after,
) {
  // Keep the order stable and meaningful even if the server serializes maps
  // with different key order. Unknown keys cannot enter a validated snapshot.
  const order = [
    'type',
    'text',
    'inlines',
    'level',
    'attribution',
    'ordered',
    'items',
    'itemInlines',
    'src',
    'alt',
    'caption',
    'language',
    'code',
  ];
  final names = <String>{...?before?.keys, ...?after?.keys}..remove('id');
  final sorted = names.toList()
    ..sort((a, b) {
      final ai = order.indexOf(a);
      final bi = order.indexOf(b);
      if (ai < 0 && bi < 0) return a.compareTo(b);
      if (ai < 0) return 1;
      if (bi < 0) return -1;
      return ai.compareTo(bi);
    });
  final changes = <StructuredFieldChange>[];
  for (final name in sorted) {
    final oldHas = before?.containsKey(name) ?? false;
    final newHas = after?.containsKey(name) ?? false;
    final oldValue = before?[name];
    final newValue = after?[name];
    if (oldHas != newHas ||
        !structuredComparisonJsonEquals(oldValue, newValue)) {
      changes.add(
        StructuredFieldChange(
          name: name,
          beforePresent: oldHas,
          before: oldValue,
          afterPresent: newHas,
          after: newValue,
        ),
      );
    }
  }
  return List.unmodifiable(changes);
}

/// Deep JSON equality used by read-only comparison; map order is immaterial.
bool structuredComparisonJsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!structuredComparisonJsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) ||
          !structuredComparisonJsonEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
