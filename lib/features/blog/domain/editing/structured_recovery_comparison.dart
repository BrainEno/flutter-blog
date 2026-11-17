import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// A local-only, read-only comparison of the exact base snapshot saved with a
/// recovery and the body currently held by that recovery. It never reads the
/// server, changes either document, or turns a difference into a write.
///
/// Blocks are correlated only by their validated document IDs. Position is
/// deliberately reported separately: matching IDs at different positions are
/// moves, not a destructive remove-and-insert interpretation. The comparison
/// is intentionally structural, so optional fields, formatted runs, links,
/// image captions, and values unknown to this client remain visible as data.
class StructuredRecoveryComparison {
  StructuredRecoveryComparison._({
    required this.baseVersion,
    required this.localVersion,
    required List<StructuredBlockChange> changes,
    required this.unchangedBlockCount,
  }) : changes = List<StructuredBlockChange>.unmodifiable(changes);

  final int baseVersion;
  final int localVersion;
  final List<StructuredBlockChange> changes;
  final int unchangedBlockCount;

  bool get hasChanges => changes.isNotEmpty;
  int get addedCount => _count(StructuredBlockChangeKind.added);
  int get removedCount => _count(StructuredBlockChangeKind.removed);
  int get movedCount => _count(StructuredBlockChangeKind.moved);
  int get modifiedCount => _count(StructuredBlockChangeKind.modified);

  int _count(StructuredBlockChangeKind kind) =>
      changes.where((change) => change.kinds.contains(kind)).length;

  /// Compares two already-valid immutable documents. A version change is not a
  /// document edit this local viewer can interpret safely, so it is reported as
  /// unsupported instead of guessing correspondence between different schemas.
  static StructuredRecoveryComparison compare({
    required StructuredArticleDraft base,
    required StructuredArticleDraft local,
  }) {
    if (base.version != local.version) {
      throw const FormatException('Cannot compare different document versions');
    }

    final baseById = <String, _IndexedBlock>{
      for (var index = 0; index < base.blocks.length; index++)
        base.blocks[index]['id'] as String: _IndexedBlock(
          index: index,
          block: base.blocks[index],
        ),
    };
    final localById = <String, _IndexedBlock>{
      for (var index = 0; index < local.blocks.length; index++)
        local.blocks[index]['id'] as String: _IndexedBlock(
          index: index,
          block: local.blocks[index],
        ),
    };

    final changes = <StructuredBlockChange>[];
    var unchanged = 0;

    // Follow the local order first: this is the order an author sees after
    // applying their own local operations. Deletions are appended in original
    // order below, where their old positions remain meaningful.
    for (var index = 0; index < local.blocks.length; index++) {
      final block = local.blocks[index];
      final id = block['id'] as String;
      final current = _IndexedBlock(index: index, block: block);
      final previous = baseById[id];
      if (previous == null) {
        changes.add(
          StructuredBlockChange._(
            id: id,
            kinds: const {StructuredBlockChangeKind.added},
            local: _snapshot(current),
          ),
        );
        continue;
      }

      final moved = previous.index != current.index;
      final fields = _fieldChanges(previous.block, current.block);
      if (!moved && fields.isEmpty) {
        unchanged++;
        continue;
      }
      changes.add(
        StructuredBlockChange._(
          id: id,
          kinds: {
            if (moved) StructuredBlockChangeKind.moved,
            if (fields.isNotEmpty) StructuredBlockChangeKind.modified,
          },
          base: _snapshot(previous),
          local: _snapshot(current),
          fields: fields,
        ),
      );
    }

    for (var index = 0; index < base.blocks.length; index++) {
      final block = base.blocks[index];
      final id = block['id'] as String;
      if (localById.containsKey(id)) continue;
      changes.add(
        StructuredBlockChange._(
          id: id,
          kinds: const {StructuredBlockChangeKind.removed},
          base: _snapshot(_IndexedBlock(index: index, block: block)),
        ),
      );
    }

    return StructuredRecoveryComparison._(
      baseVersion: base.version,
      localVersion: local.version,
      changes: changes,
      unchangedBlockCount: unchanged,
    );
  }
}

/// Each kind describes one aspect of a block change. A single surviving block
/// may be both [moved] and [modified]. Added and removed blocks never claim a
/// pairing, even if their visible text happens to be the same.
enum StructuredBlockChangeKind { added, removed, moved, modified }

/// A correlated structural change. [base] and [local] are defensive snapshots,
/// not references into either recovery document, so a review surface cannot
/// mutate data used by a later local compare-and-swap write.
class StructuredBlockChange {
  StructuredBlockChange._({
    required this.id,
    required Set<StructuredBlockChangeKind> kinds,
    this.base,
    this.local,
    List<StructuredBlockFieldChange> fields = const [],
  }) : kinds = Set<StructuredBlockChangeKind>.unmodifiable(kinds),
       fields = List<StructuredBlockFieldChange>.unmodifiable(fields) {
    if (id.isEmpty || kinds.isEmpty || (base == null && local == null)) {
      throw ArgumentError('Incomplete structured block comparison');
    }
  }

  final String id;
  final Set<StructuredBlockChangeKind> kinds;
  final StructuredBlockSnapshot? base;
  final StructuredBlockSnapshot? local;
  final List<StructuredBlockFieldChange> fields;

  bool get wasAdded => kinds.contains(StructuredBlockChangeKind.added);
  bool get wasRemoved => kinds.contains(StructuredBlockChangeKind.removed);
  bool get wasMoved => kinds.contains(StructuredBlockChangeKind.moved);
  bool get wasModified => kinds.contains(StructuredBlockChangeKind.modified);
}

/// One exact block snapshot used only for review. [fields] includes `id` and
/// `type`, preserving all optional and future fields even when this app has no
/// specialized editor for them.
class StructuredBlockSnapshot {
  StructuredBlockSnapshot._({
    required this.position,
    required this.id,
    required this.type,
    required Map<String, Object?> fields,
  }) : fields = Map<String, Object?>.unmodifiable(fields);

  /// Zero-based document position. The UI may add one for human-facing copy.
  final int position;
  final String id;
  final String type;
  final Map<String, Object?> fields;

  Object? operator [](String key) => fields[key];
}

/// A field that changed in a block which exists in both snapshots. [before] or
/// [after] being null is distinct from a missing map key; use [hadBefore] and
/// [hasAfter] to render that distinction without inventing a value.
class StructuredBlockFieldChange {
  StructuredBlockFieldChange._({
    required this.field,
    required this.hadBefore,
    required this.before,
    required this.hasAfter,
    required this.after,
  });

  final String field;
  final bool hadBefore;
  final Object? before;
  final bool hasAfter;
  final Object? after;
}

class _IndexedBlock {
  const _IndexedBlock({required this.index, required this.block});
  final int index;
  final Map<String, Object?> block;
}

StructuredBlockSnapshot _snapshot(_IndexedBlock indexed) {
  final block = _copyBlock(indexed.block);
  final id = block['id'];
  final type = block['type'];
  if (id is! String || type is! String) {
    throw const FormatException('Structured document block is malformed');
  }
  return StructuredBlockSnapshot._(
    position: indexed.index,
    id: id,
    type: type,
    fields: block,
  );
}

List<StructuredBlockFieldChange> _fieldChanges(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final keys = <String>{...before.keys, ...after.keys}.toList()..sort();
  return List<StructuredBlockFieldChange>.unmodifiable([
    for (final key in keys)
      if (key != 'id' &&
          (before.containsKey(key) != after.containsKey(key) ||
              !_sameValue(before[key], after[key])))
        StructuredBlockFieldChange._(
          field: key,
          hadBefore: before.containsKey(key),
          before: _freezeValue(before[key]),
          hasAfter: after.containsKey(key),
          after: _freezeValue(after[key]),
        ),
  ]);
}

Map<String, Object?> _copyBlock(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in source.entries) entry.key: _freezeValue(entry.value),
    });

Object? _freezeValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map<Object?>((entry) => _freezeValue(entry)),
    );
  }
  if (value is Map) {
    final copy = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Structured field key is malformed');
      }
      copy[entry.key as String] = _freezeValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(copy);
  }
  throw const FormatException('Structured field value is unsupported');
}

bool _sameValue(Object? before, Object? after) {
  if (identical(before, after) || before == after) return true;
  if (before is List && after is List) {
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (!_sameValue(before[index], after[index])) return false;
    }
    return true;
  }
  if (before is Map && after is Map) {
    if (before.length != after.length) return false;
    for (final key in before.keys) {
      if (!after.containsKey(key) || !_sameValue(before[key], after[key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}
