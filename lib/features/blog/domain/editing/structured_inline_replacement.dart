import 'dart:convert';

import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// Explicit attributes for newly inserted text; no surrounding style or link
/// is inherited. Null marks mean an absent key, while [] is explicitly empty.
/// The object owns its marks list, so a caller cannot mutate an accepted edit.
class StructuredInsertedText {
  StructuredInsertedText({required this.text, List<String>? marks, this.href})
    : marks = marks == null ? null : List<String>.unmodifiable(marks) {
    if (text.isEmpty || text.length > 20000 || !isWellFormedUtf16(text)) {
      throw const FormatException('Invalid inserted text');
    }
    final styles = this.marks;
    if (styles != null &&
        (styles.length > supportedMarks.length ||
            styles.toSet().length != styles.length ||
            styles.any((mark) => !supportedMarks.contains(mark)))) {
      throw const FormatException('Invalid inserted marks');
    }
    if (href != null &&
        (!isWellFormedUtf16(href!) || !isValidArticleResourceUrl(href!))) {
      throw const FormatException('Invalid inserted link');
    }
  }

  static const supportedMarks = <String>{
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'code',
  };
  final String text;
  final List<String>? marks;
  final String? href;

  Map<String, Object?> _run() => {
    'text': text,
    if (marks != null) 'marks': marks,
    if (href != null) 'href': href,
  };

  bool get _plain => marks == null && href == null;
}

/// A deliberate replacement in one v1 text block or explicitly indexed list
/// item. Offsets are UTF-16 code units relative to the exact captured fallback.
/// A collapsed range is an insertion; null inserted text means deletion.
///
/// This is an isolated immutable operation, not an input-method adapter, a
/// durable intermediate buffer, an identity fence, a local CAS token or a
/// remote write version. Callers must fence account, route and storage, drop
/// captures after any intervening body change, and retain invalid IME input
/// separately. It never infers attributes or merges neighboring runs.
class StructuredInlineReplacement {
  StructuredInlineReplacement._({
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

  factory StructuredInlineReplacement.textBlock({
    required StructuredArticleDraft document,
    required String blockId,
    required int start,
    required int end,
  }) {
    _requireVersion(document);
    final block = _block(document, blockId);
    if (!const {'paragraph', 'heading', 'quote'}.contains(block['type'])) {
      throw ArgumentError('Replacement target is not a text block');
    }
    final text = block['text'] as String;
    _validateRange(text, start, end);
    final explicit = block.containsKey('inlines');
    final runs = explicit
        ? _copyRuns(block['inlines'] as List)
        : <Map<String, Object?>>[
            {'text': text},
          ];
    return StructuredInlineReplacement._(
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

  factory StructuredInlineReplacement.listItem({
    required StructuredArticleDraft document,
    required String blockId,
    required int itemIndex,
    required int start,
    required int end,
  }) {
    _requireVersion(document);
    final block = _block(document, blockId);
    if (block['type'] != 'list') {
      throw ArgumentError('Replacement target is not a list');
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
    return StructuredInlineReplacement._(
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

  /// Return a validated new document or throw without modifying [current].
  /// Empty insertion/deletion is a no-op. On an unformatted target, a plain
  /// replacement preserves the absence of inline fields. Otherwise the exact
  /// inserted attributes are used, even if the replacement text is unchanged.
  StructuredArticleDraft apply(
    StructuredArticleDraft current, {
    StructuredInsertedText? inserted,
  }) {
    if (_snapshotOf(current) != _snapshot) {
      throw StateError('Replacement source changed');
    }
    if (start == end && inserted == null) return current;
    final newText =
        text.substring(0, start) + (inserted?.text ?? '') + text.substring(end);
    final item = itemIndex;
    if (!_explicitRuns && (inserted == null || inserted._plain)) {
      if (newText == text) return current;
      return item == null
          ? current.replacePlainText(blockId, newText)
          : current.replacePlainListItem(blockId, item, newText);
    }
    final result = <Map<String, Object?>>[];
    var position = 0;
    for (final run in _runs) {
      final value = run['text'] as String;
      final next = position + value.length;
      final count = (start - position).clamp(0, value.length);
      if (count > 0) result.add({...run, 'text': value.substring(0, count)});
      position = next;
    }
    if (inserted != null) result.add(inserted._run());
    position = 0;
    for (final run in _runs) {
      final value = run['text'] as String;
      final next = position + value.length;
      final offset = (end - position).clamp(0, value.length);
      if (offset < value.length) {
        result.add({...run, 'text': value.substring(offset)});
      }
      position = next;
    }
    if (result.length > 1000) {
      throw const FormatException('Too many inline runs');
    }
    if (item == null) return current.replaceTextRuns(blockId, result);
    if (_explicitRuns) {
      return current.replaceListItemRuns(blockId, item, result);
    }
    final block = _block(current, blockId);
    final items = block['items'] as List;
    final allRuns = <List<Map<String, Object?>>>[
      for (var i = 0; i < items.length; i++)
        i == item
            ? result
            : <Map<String, Object?>>[
                {'text': items[i]},
              ],
    ];
    final newItems = List<Object?>.of(items)..[item] = newText;
    return current.replace(blockId, {
      ...block,
      'items': newItems,
      'itemInlines': allRuns,
    });
  }
}

void _requireVersion(StructuredArticleDraft body) {
  if (body.version != 1) {
    throw StateError('Replacement requires document version 1');
  }
}

Map<String, Object?> _block(StructuredArticleDraft body, String id) {
  for (final block in body.blocks) {
    if (block['id'] == id) return block;
  }
  throw ArgumentError.value(id, 'blockId', 'Unknown block');
}

String _snapshotOf(StructuredArticleDraft body) =>
    jsonEncode([body.version, body.blocks]);

List<Map<String, Object?>> _copyRuns(List runs) => [
  for (final run in runs) Map<String, Object?>.from(run as Map),
];

void _validateRange(String text, int start, int end) {
  if (start < 0 || start > end || end > text.length) {
    throw RangeError('Replacement range must be within the target');
  }
  if (!isWellFormedUtf16(text)) {
    throw const FormatException('Target text cannot be safely rendered');
  }
  if (_splitsSurrogate(text, start) || _splitsSurrogate(text, end)) {
    throw const FormatException('Replacement splits a surrogate pair');
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
