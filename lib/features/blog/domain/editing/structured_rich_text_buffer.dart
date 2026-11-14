import 'dart:convert';

import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// One exact local intermediate run. Empty and unpaired UTF-16 are retained,
/// not repaired. Attributes remain explicit; absent marks differ from [].
class StructuredRichBufferRun {
  StructuredRichBufferRun({required this.text, List<String>? marks, this.href})
    : marks = marks == null ? null : List<String>.unmodifiable(marks) {
    final styles = this.marks;
    if (text.length > 20000 ||
        (styles != null &&
            (styles.length > _marks.length ||
                styles.toSet().length != styles.length ||
                styles.any((m) => !_marks.contains(m)))) ||
        (href != null && !isValidArticleResourceUrl(href!))) {
      throw const FormatException('Invalid rich buffer run');
    }
  }
  static const _marks = {
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'code',
  };
  final String text;
  final List<String>? marks;
  final String? href;

  Map<String, Object?> _storage() => {
    'units': text.codeUnits,
    if (marks != null) 'marks': marks,
    if (href != null) 'hrefUnits': href!.codeUnits,
  };
  Map<String, Object?> _document() => {
    'text': text,
    if (marks != null) 'marks': marks,
    if (href != null) 'href': href,
  };
}

/// Versioned, local-only intermediate state for an existing formatted target.
/// It stores UTF-16 code units numerically to avoid lossy UTF-8 conversion of
/// an unmatched surrogate. It does not authorize or publish anything, and is
/// not a session, a CAS token, or a claim that an IME state can be restored.
class StructuredRichTextBuffer {
  StructuredRichTextBuffer({
    required this.blockId,
    required this.itemIndex,
    required List<StructuredRichBufferRun> runs,
    required this.selectionBase,
    required this.selectionExtent,
    required this.composingStart,
    required this.composingEnd,
  }) : runs = List<StructuredRichBufferRun>.unmodifiable(runs) {
    if (blockId.isEmpty ||
        blockId != blockId.trim() ||
        blockId.length > 100 ||
        (itemIndex != null && (itemIndex! < 0 || itemIndex! >= 100)) ||
        runs.length > 1000) {
      throw const FormatException('Invalid rich buffer target or run count');
    }
    var length = 0;
    for (final run in runs) {
      length += run.text.length;
      if (length > 20000) {
        throw const FormatException('Rich buffer text too long');
      }
    }
    if (!_selectionValid(selectionBase, selectionExtent, length) ||
        !_compositionValid(composingStart, composingEnd, length)) {
      throw const FormatException('Invalid rich buffer offsets');
    }
    if (encode().length > maxEncodedLength) {
      throw const FormatException('Rich buffer too large');
    }
  }

  static const maxEncodedLength = 1500000;
  final String blockId;
  final int? itemIndex;
  final List<StructuredRichBufferRun> runs;
  final int selectionBase;
  final int selectionExtent;
  final int composingStart;
  final int composingEnd;
  String get text => runs.map((run) => run.text).join();

  Map<String, Object?> toJson() => {
    'schema': 2,
    'blockIdUnits': blockId.codeUnits,
    'itemIndex': itemIndex,
    'runs': [for (final run in runs) run._storage()],
    'selectionBase': selectionBase,
    'selectionExtent': selectionExtent,
    'composingStart': composingStart,
    'composingEnd': composingEnd,
  };
  String encode() => jsonEncode(toJson());

  static StructuredRichTextBuffer decode(String encoded) {
    if (encoded.length > maxEncodedLength) {
      throw const FormatException('Rich buffer too large');
    }
    final value = jsonDecode(encoded);
    const fields = {
      'schema',
      'blockIdUnits',
      'itemIndex',
      'runs',
      'selectionBase',
      'selectionExtent',
      'composingStart',
      'composingEnd',
    };
    if (value is! Map ||
        value.length != fields.length ||
        value.keys.any((key) => !fields.contains(key)) ||
        value['schema'] is! int ||
        value['schema'] != 2 ||
        (value['itemIndex'] != null && value['itemIndex'] is! int) ||
        value['runs'] is! List ||
        (value['runs'] as List).length > 1000 ||
        value['selectionBase'] is! int ||
        value['selectionExtent'] is! int ||
        value['composingStart'] is! int ||
        value['composingEnd'] is! int) {
      throw const FormatException('Invalid rich buffer fields');
    }
    final runs = <StructuredRichBufferRun>[];
    for (final raw in value['runs'] as List) {
      if (raw is! Map ||
          !raw.containsKey('units') ||
          raw.keys.any(
            (key) => !const {'units', 'marks', 'hrefUnits'}.contains(key),
          ) ||
          (raw.containsKey('marks') &&
              (raw['marks'] is! List ||
                  (raw['marks'] as List).any((m) => m is! String)))) {
        throw const FormatException('Invalid rich buffer run fields');
      }
      runs.add(
        StructuredRichBufferRun(
          text: _decodeUnits(raw['units'], 20000),
          marks: raw.containsKey('marks')
              ? (raw['marks'] as List).cast<String>()
              : null,
          href: raw.containsKey('hrefUnits')
              ? _decodeUnits(raw['hrefUnits'], 2048)
              : null,
        ),
      );
    }
    return StructuredRichTextBuffer(
      blockId: _decodeUnits(value['blockIdUnits'], 100),
      itemIndex: value['itemIndex'] as int?,
      runs: runs,
      selectionBase: value['selectionBase'] as int,
      selectionExtent: value['selectionExtent'] as int,
      composingStart: value['composingStart'] as int,
      composingEnd: value['composingEnd'] as int,
    );
  }

  /// Validate a target against its exact immutable parent. List items have no
  /// stable IDs; persistence must compare the entire parent and raw buffer.
  void validateTarget(StructuredArticleDraft body) {
    if (body.version != 1) {
      throw const FormatException('Rich buffer requires v1');
    }
    final matches = body.blocks.where((block) => block['id'] == blockId);
    if (matches.length != 1) {
      throw const FormatException('Missing rich buffer target');
    }
    final block = matches.single;
    final item = itemIndex;
    if (item == null) {
      if (!const {'paragraph', 'heading', 'quote'}.contains(block['type']) ||
          !block.containsKey('inlines')) {
        throw const FormatException('Rich buffer requires formatted text');
      }
    } else if (block['type'] != 'list' ||
        !block.containsKey('itemInlines') ||
        item >= (block['items'] as List).length) {
      throw const FormatException('Rich buffer requires formatted list item');
    }
  }

  /// Produces a validated body only for finished, renderable runs. It never
  /// mutates or clears this buffer on rejection; callers must CAS the parent.
  StructuredArticleDraft applyTo(StructuredArticleDraft body) {
    validateTarget(body);
    if (composingStart != -1 && composingStart != composingEnd) {
      throw const FormatException('Composition is still active');
    }
    for (final run in runs) {
      if (!isWellFormedUtf16(run.text) ||
          (run.href != null && !isWellFormedUtf16(run.href!))) {
        throw const FormatException('Run cannot be rendered safely');
      }
    }
    final next = [for (final run in runs) run._document()];
    final item = itemIndex;
    return item == null
        ? body.replaceTextRuns(blockId, next)
        : body.replaceListItemRuns(blockId, item, next);
  }
}

bool _selectionValid(int base, int extent, int length) =>
    (base == -1 && extent == -1) ||
    (base >= 0 && extent >= 0 && base <= length && extent <= length);
bool _compositionValid(int start, int end, int length) =>
    (start == -1 && end == -1) || (start >= 0 && start <= end && end <= length);

String _decodeUnits(Object? value, int maxLength) {
  if (value is! List ||
      value.length > maxLength ||
      value.any((v) => v is! int || v < 0 || v > 65535)) {
    throw const FormatException('Invalid UTF-16 units');
  }
  return String.fromCharCodes(value.cast<int>());
}
