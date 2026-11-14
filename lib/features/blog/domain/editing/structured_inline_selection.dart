import 'dart:convert';

import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// An explicit half-open range in one structured text block or list item.
///
/// Offsets are UTF-16 code units, as in Flutter selections and the upstream
/// document contract. This component never interprets Markdown, performs text
/// insertion, merges runs, or resolves a link. It is not a persistence token or
/// authorization fence. The caller must separately fence account, route and
/// CAS writes, and must not keep selections after their identity changes.
///
/// A selection captures the entire immutable source document. Applying it to
/// a structurally different snapshot fails rather than guessing where a stale
/// range belongs. Consumers must obtain a fresh selection after any edit.
class StructuredInlineSelection {
  StructuredInlineSelection._({
    required this.blockId,
    required this.itemIndex,
    required this.start,
    required this.end,
    required this.text,
    required String snapshot,
    required List<Map<String, Object?>> runs,
    required bool explicitRuns,
  }) : _snapshot = snapshot,
       _runs = runs,
       _explicitRuns = explicitRuns;

  /// Captures a nonempty range in a paragraph, heading or quote.
  factory StructuredInlineSelection.textBlock({
    required StructuredArticleDraft document,
    required String blockId,
    required int start,
    required int end,
  }) {
    _requireVersion(document);
    final block = _findBlock(document, blockId);
    if (!const {'paragraph', 'heading', 'quote'}.contains(block['type'])) {
      throw ArgumentError('Selection target is not a text block');
    }
    final text = block['text'] as String;
    _validateRange(text, start, end);
    final explicit = block.containsKey('inlines');
    final runs = explicit
        ? _copyRuns(block['inlines'] as List)
        : <Map<String, Object?>>[
            {'text': text},
          ];
    return StructuredInlineSelection._(
      blockId: blockId,
      itemIndex: null,
      start: start,
      end: end,
      text: text,
      snapshot: _snapshotOf(document),
      runs: runs,
      explicitRuns: explicit,
    );
  }

  /// Captures a nonempty range in one list item. An unformatted list is
  /// promoted only if an operation actually changes the selected range.
  factory StructuredInlineSelection.listItem({
    required StructuredArticleDraft document,
    required String blockId,
    required int itemIndex,
    required int start,
    required int end,
  }) {
    _requireVersion(document);
    final block = _findBlock(document, blockId);
    if (block['type'] != 'list') {
      throw ArgumentError('Selection target is not a list');
    }
    final items = block['items'] as List;
    RangeError.checkValidIndex(itemIndex, items, 'itemIndex');
    final text = items[itemIndex] as String;
    _validateRange(text, start, end);
    final explicit = block.containsKey('itemInlines');
    final runs = explicit
        ? _copyRuns((block['itemInlines'] as List)[itemIndex] as List)
        : <Map<String, Object?>>[
            {'text': text},
          ];
    return StructuredInlineSelection._(
      blockId: blockId,
      itemIndex: itemIndex,
      start: start,
      end: end,
      text: text,
      snapshot: _snapshotOf(document),
      runs: runs,
      explicitRuns: explicit,
    );
  }

  final String blockId;
  final int? itemIndex;
  final int start;
  final int end;
  final String text;
  final String _snapshot;
  final List<Map<String, Object?>> _runs;
  final bool _explicitRuns;

  static const supportedMarks = <String>{
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'code',
  };

  /// Set one supported mark throughout the range. Existing mark order is
  /// preserved; a newly enabled mark is appended only to the affected runs.
  /// A true no-op returns [current] itself and never introduces inline keys.
  StructuredArticleDraft setMark(
    StructuredArticleDraft current,
    String mark, {
    required bool enabled,
  }) {
    _requireCurrent(current);
    if (!supportedMarks.contains(mark)) {
      throw ArgumentError.value(mark, 'mark', 'Unsupported inline mark');
    }
    return _apply(current, (run) {
      final original = run['marks'];
      final marks = original == null
          ? <String>[]
          : List<String>.of((original as List).cast<String>());
      final contains = marks.contains(mark);
      if (contains == enabled) return false;
      if (enabled) {
        marks.add(mark);
      } else {
        marks.remove(mark);
      }
      run['marks'] = marks;
      return true;
    });
  }

  /// Set an exact, validated link on the range, or remove it with null.
  /// Unsafe URLs are rejected even if the selected text has no link already.
  /// No URL is normalized or opened by this component.
  StructuredArticleDraft setLink(StructuredArticleDraft current, String? href) {
    _requireCurrent(current);
    if (href != null && !isValidArticleResourceUrl(href)) {
      throw const FormatException('Invalid inline URL');
    }
    return _apply(current, (run) {
      if (href == null) {
        if (!run.containsKey('href')) return false;
        run.remove('href');
      } else {
        if (run['href'] == href) return false;
        run['href'] = href;
      }
      return true;
    });
  }

  void _requireCurrent(StructuredArticleDraft current) {
    if (_snapshotOf(current) != _snapshot) {
      throw StateError('Selection source changed');
    }
  }

  StructuredArticleDraft _apply(
    StructuredArticleDraft current,
    bool Function(Map<String, Object?> run) update,
  ) {
    final result = <Map<String, Object?>>[];
    var position = 0;
    var changed = false;
    for (final original in _runs) {
      final value = original['text'] as String;
      final next = position + value.length;
      final selectedStart = start > position ? start : position;
      final selectedEnd = end < next ? end : next;
      if (selectedStart >= selectedEnd) {
        result.add(Map<String, Object?>.of(original));
        position = next;
        continue;
      }
      final selected = Map<String, Object?>.of(original);
      if (!update(selected)) {
        result.add(Map<String, Object?>.of(original));
        position = next;
        continue;
      }
      changed = true;
      final left = selectedStart - position;
      final right = selectedEnd - position;
      if (left > 0) {
        result.add({...original, 'text': value.substring(0, left)});
      }
      selected['text'] = value.substring(left, right);
      result.add(selected);
      if (right < value.length) {
        result.add({...original, 'text': value.substring(right)});
      }
      position = next;
    }
    if (!changed) return current;
    // The validated document owns the limit and is the only source of a new
    // snapshot. Never merge adjacent runs to make an oversized edit pass.
    if (result.length > 1000) {
      throw const FormatException('Too many inline runs');
    }
    final selectedItem = itemIndex;
    if (selectedItem == null) {
      return current.replaceTextRuns(blockId, result);
    }
    if (_explicitRuns) {
      return current.replaceListItemRuns(blockId, selectedItem, result);
    }
    final block = _findBlock(current, blockId);
    final items = block['items'] as List;
    final all = <List<Map<String, Object?>>>[
      for (var i = 0; i < items.length; i++)
        i == selectedItem
            ? result
            : <Map<String, Object?>>[
                {'text': items[i]},
              ],
    ];
    return current.replace(blockId, {...block, 'itemInlines': all});
  }
}

void _requireVersion(StructuredArticleDraft document) {
  if (document.version != 1) {
    throw StateError('Inline formatting requires document version 1');
  }
}

Map<String, Object?> _findBlock(StructuredArticleDraft document, String id) {
  for (final block in document.blocks) {
    if (block['id'] == id) return block;
  }
  throw ArgumentError.value(id, 'blockId', 'Unknown block');
}

String _snapshotOf(StructuredArticleDraft document) =>
    jsonEncode([document.version, document.blocks]);

List<Map<String, Object?>> _copyRuns(List runs) => [
  for (final run in runs) Map<String, Object?>.from(run as Map),
];

void _validateRange(String text, int start, int end) {
  if (start < 0 || start >= end || end > text.length) {
    throw RangeError('Selection must be nonempty and within text');
  }
  if (_splitsSurrogate(text, start) || _splitsSurrogate(text, end)) {
    throw const FormatException('Selection splits a UTF-16 surrogate pair');
  }
}

bool _splitsSurrogate(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return false;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff;
}
