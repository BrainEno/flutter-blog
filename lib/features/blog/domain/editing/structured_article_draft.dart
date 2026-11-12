import 'dart:convert';

import 'package:belog/core/utils/article_resource_url.dart';

/// An immutable, lossless editing snapshot of the server's v0/v1 block format.
///
/// This is a local editing primitive, not authorization or a concurrency
/// guarantee. Callers must not submit it until the remote write path has its
/// own account/edition fence and conflict handling. Optional fields are kept
/// exactly as supplied; rendered text is never used to reconstruct a document.
/// Each operation validates a new snapshot before returning it, so a rejected
/// edit leaves the previous snapshot untouched.
class StructuredArticleDraft {
  StructuredArticleDraft._(this.version, this._blocks);

  factory StructuredArticleDraft.parse({
    required Object? version,
    required Object? blocks,
  }) {
    if (version is! int || (version != 0 && version != 1)) {
      throw const FormatException('Unsupported article version');
    }
    if (blocks is! List || blocks.isEmpty || blocks.length > 200) {
      throw const FormatException('Invalid block count');
    }
    // Copy before checking or storing: no caller-owned map or list can later
    // mutate an accepted snapshot. JSON also rejects non-JSON values.
    final Object? copied;
    try {
      final encoded = jsonEncode(blocks);
      if (encoded.length > 1000000) {
        throw const FormatException('Article document is too large');
      }
      copied = jsonDecode(encoded);
    } on JsonUnsupportedObjectError {
      throw const FormatException('Article document is not JSON');
    }
    if (copied is! List) throw const FormatException('Invalid blocks');
    final ids = <String>{};
    final parsed = <Map<String, Object?>>[];
    for (final value in copied) {
      final block = _map(value);
      _validateBlock(block, version);
      if (!ids.add(block['id'] as String)) {
        throw const FormatException('Duplicate block id');
      }
      parsed.add(_freezeMap(block));
    }
    return StructuredArticleDraft._(version, List.unmodifiable(parsed));
  }

  final int version;
  final List<Map<String, Object?>> _blocks;

  /// Deeply immutable block maps in their original order. Presence of optional
  /// keys, run boundaries, whitespace and block ids are significant.
  List<Map<String, Object?>> get blocks => _blocks;

  /// Detached, mutable JSON suitable for a local snapshot or eventual wire
  /// encoding. Mutating the result cannot mutate this document.
  List<Map<String, dynamic>> toJsonBlocks() =>
      (jsonDecode(jsonEncode(_blocks)) as List).cast<Map<String, dynamic>>();

  StructuredArticleDraft _withBlocks(List<Map<String, Object?>> blocks) =>
      StructuredArticleDraft.parse(version: version, blocks: blocks);

  int _indexOf(String id) {
    final index = _blocks.indexWhere((block) => block['id'] == id);
    if (index < 0) throw ArgumentError.value(id, 'id', 'Unknown block');
    return index;
  }

  /// Inserts an explicitly created block. The complete block is validated,
  /// including its id and all optional fields. [index] may be at the end.
  StructuredArticleDraft insert(int index, Map<String, Object?> block) {
    if (index < 0 || index > _blocks.length) {
      throw RangeError.range(index, 0, _blocks.length, 'index');
    }
    final next = List<Map<String, Object?>>.of(_blocks)..insert(index, block);
    return _withBlocks(next);
  }

  /// Removes one block. A document must still contain at least one block.
  StructuredArticleDraft remove(String id) {
    final index = _indexOf(id);
    final next = List<Map<String, Object?>>.of(_blocks)..removeAt(index);
    return _withBlocks(next);
  }

  /// Moves a block to its final zero-based position in the resulting list.
  StructuredArticleDraft move(String id, int destination) {
    if (destination < 0 || destination >= _blocks.length) {
      throw RangeError.range(destination, 0, _blocks.length - 1, 'destination');
    }
    final from = _indexOf(id);
    final next = List<Map<String, Object?>>.of(_blocks);
    final block = next.removeAt(from);
    next.insert(destination, block);
    return _withBlocks(next);
  }

  /// Replaces a complete block, preserving identity. The caller must supply
  /// every field it intends to keep; there is no implicit flattening.
  StructuredArticleDraft replace(String id, Map<String, Object?> block) {
    final index = _indexOf(id);
    if (block['id'] != id) throw ArgumentError('Block identity cannot change');
    final next = List<Map<String, Object?>>.of(_blocks)..[index] = block;
    return _withBlocks(next);
  }

  /// Changes text only when there are no explicit inline runs. Refusing this
  /// operation for formatted text prevents accidental loss of marks or links.
  /// Use [replaceTextRuns] for a deliberate formatted edit instead.
  StructuredArticleDraft replacePlainText(String id, String text) {
    final block = _blocks[_indexOf(id)];
    if (!const {'paragraph', 'heading', 'quote'}.contains(block['type'])) {
      throw ArgumentError('Block is not text');
    }
    if (block.containsKey('inlines')) {
      throw StateError('Formatted text requires explicit runs');
    }
    return replace(id, {...block, 'text': text});
  }

  /// Replaces explicit inline runs and derives their fallback text. This
  /// requires v1 and does not infer formatting from Markdown or HTML.
  StructuredArticleDraft replaceTextRuns(
    String id,
    List<Map<String, Object?>> runs,
  ) {
    final block = _blocks[_indexOf(id)];
    if (!const {'paragraph', 'heading', 'quote'}.contains(block['type'])) {
      throw ArgumentError('Block is not text');
    }
    final text = _joinedRuns(runs);
    return replace(id, {...block, 'text': text, 'inlines': runs});
  }

  /// Applies or removes a mark on one run. All other runs and the selected
  /// run's link and text remain intact. A plain v1 text block is treated as
  /// one run, allowing formatting to be added without parsing its contents.
  StructuredArticleDraft setTextRunMark(
    String id,
    int runIndex,
    String mark, {
    required bool enabled,
  }) {
    final runs = _textRuns(id);
    _setRunMark(runs, runIndex, mark, enabled: enabled);
    return replaceTextRuns(id, runs);
  }

  /// Set a link on one run, or remove it with null. URL validation happens
  /// before a new document is returned; an unsafe URL is never normalized.
  StructuredArticleDraft setTextRunLink(String id, int runIndex, String? href) {
    final runs = _textRuns(id);
    _setRunLink(runs, runIndex, href);
    return replaceTextRuns(id, runs);
  }

  List<Map<String, Object?>> _textRuns(String id) {
    final block = _blocks[_indexOf(id)];
    if (!const {'paragraph', 'heading', 'quote'}.contains(block['type'])) {
      throw ArgumentError('Block is not text');
    }
    final value = block['inlines'];
    if (value == null) {
      return [
        {'text': block['text']},
      ];
    }
    return [
      for (final run in value as List) Map<String, Object?>.of(_map(run)),
    ];
  }

  /// Applies a mark to a single list item run without changing other items.
  /// Plain lists can be promoted to v1 inlines without losing item whitespace.
  StructuredArticleDraft setListRunMark(
    String id,
    int itemIndex,
    int runIndex,
    String mark, {
    required bool enabled,
  }) {
    final all = _listRuns(id);
    RangeError.checkValidIndex(itemIndex, all, 'itemIndex');
    _setRunMark(all[itemIndex], runIndex, mark, enabled: enabled);
    return _replaceAllListRuns(id, all);
  }

  StructuredArticleDraft setListRunLink(
    String id,
    int itemIndex,
    int runIndex,
    String? href,
  ) {
    final all = _listRuns(id);
    RangeError.checkValidIndex(itemIndex, all, 'itemIndex');
    _setRunLink(all[itemIndex], runIndex, href);
    return _replaceAllListRuns(id, all);
  }

  List<List<Map<String, Object?>>> _listRuns(String id) {
    final block = _blocks[_indexOf(id)];
    if (block['type'] != 'list') throw ArgumentError('Block is not a list');
    final inline = block['itemInlines'];
    if (inline is! List) {
      return [
        for (final text in block['items'] as List)
          [
            {'text': text},
          ],
      ];
    }
    return [
      for (final item in inline)
        [for (final run in item as List) Map<String, Object?>.of(_map(run))],
    ];
  }

  StructuredArticleDraft _replaceAllListRuns(
    String id,
    List<List<Map<String, Object?>>> runs,
  ) {
    final block = _blocks[_indexOf(id)];
    return replace(id, {
      ...block,
      'items': [for (final item in runs) _joinedRuns(item)],
      'itemInlines': runs,
    });
  }

  /// Changes a list item's fallback only when the block has no inline runs.
  /// Other items and every other property of the block remain untouched.
  StructuredArticleDraft replacePlainListItem(
    String id,
    int index,
    String text,
  ) {
    final block = _blocks[_indexOf(id)];
    if (block['type'] != 'list') throw ArgumentError('Block is not a list');
    if (block.containsKey('itemInlines')) {
      throw StateError('Formatted list requires explicit runs');
    }
    final items = List<Object?>.of(block['items'] as List);
    RangeError.checkValidIndex(index, items, 'index');
    items[index] = text;
    return replace(id, {...block, 'items': items});
  }

  /// Changes one formatted item while retaining all other items' exact runs.
  /// An unformatted list cannot be silently converted by this operation.
  StructuredArticleDraft replaceListItemRuns(
    String id,
    int index,
    List<Map<String, Object?>> runs,
  ) {
    final block = _blocks[_indexOf(id)];
    if (block['type'] != 'list') throw ArgumentError('Block is not a list');
    final originalRuns = block['itemInlines'];
    if (originalRuns is! List) throw StateError('List has no inline runs');
    final items = List<Object?>.of(block['items'] as List);
    RangeError.checkValidIndex(index, items, 'index');
    final allRuns = List<Object?>.of(originalRuns);
    items[index] = _joinedRuns(runs);
    allRuns[index] = runs;
    return replace(id, {...block, 'items': items, 'itemInlines': allRuns});
  }
}

const _inlineMarks = {'bold', 'italic', 'underline', 'strikethrough', 'code'};

void _setRunMark(
  List<Map<String, Object?>> runs,
  int index,
  String mark, {
  required bool enabled,
}) {
  RangeError.checkValidIndex(index, runs, 'runIndex');
  if (!_inlineMarks.contains(mark)) throw ArgumentError.value(mark, 'mark');
  final run = runs[index];
  final marks = List<String>.of((run['marks'] as List?)?.cast<String>() ?? []);
  if (enabled && !marks.contains(mark)) marks.add(mark);
  if (!enabled) marks.remove(mark);
  // Keep an originally absent marks field absent when the action is a no-op.
  if (marks.isEmpty && !run.containsKey('marks')) return;
  run['marks'] = marks;
}

void _setRunLink(List<Map<String, Object?>> runs, int index, String? href) {
  RangeError.checkValidIndex(index, runs, 'runIndex');
  if (href == null) {
    runs[index].remove('href');
  } else {
    runs[index]['href'] = href;
  }
}

String _joinedRuns(List<Map<String, Object?>> runs) {
  final buffer = StringBuffer();
  for (final run in runs) {
    final text = run['text'];
    if (text is! String) throw const FormatException('Invalid inline text');
    buffer.write(text);
  }
  return buffer.toString();
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected an object');
  }
  return value.cast<String, Object?>();
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    Map.unmodifiable(value.map((key, value) => MapEntry(key, _freeze(value))));

Object? _freeze(Object? value) {
  if (value is Map) return _freezeMap(_map(value));
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

void _fields(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unsupported field');
  }
}

String _requiredText(Object? value, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value != value.trim() ||
      value.length > maxLength) {
    throw const FormatException('Invalid required text');
  }
  return value;
}

void _optionalText(Map<String, Object?> value, String key, int maxLength) {
  if (!value.containsKey(key)) return;
  final text = value[key];
  if (text is! String || text.length > maxLength) {
    throw const FormatException('Invalid optional text');
  }
}

void _validateBlock(Map<String, Object?> block, int version) {
  _requiredText(block['id'], 100);
  switch (block['type']) {
    case 'paragraph':
    case 'heading':
    case 'quote':
      final type = block['type'];
      _fields(block, {
        'id',
        'type',
        'text',
        'inlines',
        if (type == 'heading') 'level',
        if (type == 'quote') 'attribution',
      });
      final text = _requiredText(block['text'], 20000);
      if (type == 'heading') {
        final level = block['level'];
        if (level is! int || level < 2 || level > 4) {
          throw const FormatException('Invalid heading level');
        }
      }
      _optionalText(block, 'attribution', 300);
      if (block.containsKey('inlines')) {
        _validateRuns(block['inlines'], text, version);
      }
    case 'list':
      _fields(block, {'id', 'type', 'ordered', 'items', 'itemInlines'});
      final items = block['items'];
      if (block['ordered'] is! bool ||
          items is! List ||
          items.isEmpty ||
          items.length > 100) {
        throw const FormatException('Invalid list');
      }
      for (final item in items) {
        if (item is! String || item.trim().isEmpty || item.length > 2000) {
          throw const FormatException('Invalid list item');
        }
      }
      if (block.containsKey('itemInlines')) {
        final inlines = block['itemInlines'];
        if (inlines is! List || inlines.length != items.length) {
          throw const FormatException('Invalid list inline runs');
        }
        for (var i = 0; i < items.length; i++) {
          _validateRuns(inlines[i], items[i] as String, version);
        }
      }
    case 'image':
      _fields(block, {'id', 'type', 'src', 'alt', 'caption'});
      final src = _requiredText(block['src'], 2048);
      if (!isValidArticleResourceUrl(src)) {
        throw const FormatException('Invalid image URL');
      }
      if (block['alt'] is! String || (block['alt'] as String).length > 1000) {
        throw const FormatException('Invalid image alt');
      }
      _optionalText(block, 'caption', 1000);
    case 'code':
      _fields(block, {'id', 'type', 'language', 'code'});
      _requiredText(block['language'], 50);
      if (block['code'] is! String ||
          (block['code'] as String).length > 50000) {
        throw const FormatException('Invalid code');
      }
    default:
      throw const FormatException('Unsupported block type');
  }
}

void _validateRuns(Object? value, String expected, int version) {
  if (version != 1 || value is! List || value.isEmpty || value.length > 1000) {
    throw const FormatException('Invalid inline runs');
  }
  final combined = StringBuffer();
  for (final item in value) {
    final run = _map(item);
    _fields(run, {'text', 'marks', 'href'});
    final text = run['text'];
    if (text is! String || text.isEmpty || text.length > 20000) {
      throw const FormatException('Invalid inline text');
    }
    combined.write(text);
    if (run.containsKey('href')) {
      final href = run['href'];
      if (href is! String || !isValidArticleResourceUrl(href)) {
        throw const FormatException('Invalid inline URL');
      }
    }
    if (run.containsKey('marks')) {
      final marks = run['marks'];
      const allowed = _inlineMarks;
      if (marks is! List ||
          marks.length > allowed.length ||
          marks.any((mark) => mark is! String || !allowed.contains(mark)) ||
          marks.toSet().length != marks.length) {
        throw const FormatException('Invalid inline marks');
      }
    }
  }
  if (combined.toString() != expected) {
    throw const FormatException('Inline fallback does not match');
  }
}
