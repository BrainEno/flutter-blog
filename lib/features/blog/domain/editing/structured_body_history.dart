import 'dart:convert';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';

/// One validated immutable body in an ephemeral local session timeline.
/// IDs are monotonic within this history, never reused after branch truncation
/// or eviction, and have no meaning across sessions. They are not CAS tokens.
final class StructuredHistoryEntry {
  const StructuredHistoryEntry._(this.id, this.body, this.encodedUnits);
  final int id;
  final StructuredArticleDraft body;
  final int encodedUnits;
}

/// A captured timeline. References must be discarded when the owning session
/// invalidates or changes body. A view is advisory, not permission to restore.
final class StructuredHistoryView {
  const StructuredHistoryView._({
    required this.entries,
    required this.currentIndex,
    required this.generation,
    required this.truncated,
  });
  final List<StructuredHistoryEntry> entries;
  final int currentIndex;
  final int generation;
  final bool truncated;
  StructuredHistoryEntry get current => entries[currentIndex];
  bool get canUndo => currentIndex > 0;
  bool get canRedo => currentIndex + 1 < entries.length;
}

/// Bounded, in-memory history of exact body snapshots, with no persistence or
/// remote operations. [maxUnits] is a serialized UTF-16 budget, not a claim
/// about VM heap size. Callers must enforce identity, session phase and CAS.
/// All mutating calls require the exact current body or a view generation, so
/// stale UI actions cannot silently target a newer document.
final class StructuredBodyHistory {
  StructuredBodyHistory({this.maxEntries = 25, this.maxUnits = 3000000}) {
    if (maxEntries < 2 || maxUnits < 1) {
      throw ArgumentError('Invalid history bounds');
    }
  }
  final int maxEntries;
  final int maxUnits;
  final List<StructuredHistoryEntry> _entries = [];
  int _current = -1;
  int _nextId = 0;
  int _generation = 0;
  int _units = 0;
  bool _truncated = false;

  /// Begin a new history only after remote adoption or explicit recovery.
  void initialize(StructuredArticleDraft body) {
    clear();
    final entry = _makeEntry(body);
    _entries.add(entry);
    _units = entry.encodedUnits;
    _current = 0;
    _generation++;
  }

  /// Clear references on account invalidation or session close. Monotonic IDs
  /// and generation deliberately survive a reset to reject old route handoffs.
  void clear() {
    _entries.clear();
    _current = -1;
    _units = 0;
    _truncated = false;
    _generation++;
  }

  StructuredHistoryView? capture(StructuredArticleDraft current) {
    if (_current < 0 || !identical(_entries[_current].body, current)) {
      return null;
    }
    return StructuredHistoryView._(
      entries: List.unmodifiable(_entries),
      currentIndex: _current,
      generation: _generation,
      truncated: _truncated,
    );
  }

  /// Records one new edit, dropping redo history only after a real change.
  /// Equivalent bodies are no-ops, including maps with reordered keys. A null
  /// result means the input body was stale. False means an exact no-op.
  bool? record(StructuredArticleDraft before, StructuredArticleDraft after) {
    if (_current < 0 || !identical(_entries[_current].body, before)) {
      return null;
    }
    if (_sameBody(before, after)) return false;
    while (_entries.length > _current + 1) {
      _units -= _entries.removeLast().encodedUnits;
    }
    final entry = _makeEntry(after);
    _entries.add(entry);
    _units += entry.encodedUnits;
    _current = _entries.length - 1;
    while (_entries.length > 1 &&
        (_entries.length > maxEntries || _units > maxUnits)) {
      _units -= _entries.removeAt(0).encodedUnits;
      _current--;
      _truncated = true;
    }
    _generation++;
    return true;
  }

  /// Resolves and moves to an entry if neither current body nor timeline has
  /// changed since capture. Selection preserves redo entries. It does not
  /// write to disk; the owning session must queue the result through CAS.
  StructuredArticleDraft? select({
    required StructuredArticleDraft current,
    required int generation,
    required int entryId,
  }) {
    if (_current < 0 ||
        _generation != generation ||
        !identical(_entries[_current].body, current)) {
      return null;
    }
    final target = _entries.indexWhere((entry) => entry.id == entryId);
    if (target < 0 || target == _current) return null;
    _current = target;
    _generation++;
    return _entries[target].body;
  }

  StructuredHistoryEntry _makeEntry(StructuredArticleDraft body) =>
      StructuredHistoryEntry._(++_nextId, body, jsonEncode(body.blocks).length);
}

bool _sameBody(StructuredArticleDraft a, StructuredArticleDraft b) =>
    a.version == b.version &&
    structuredComparisonJsonEquals(a.blocks, b.blocks);
