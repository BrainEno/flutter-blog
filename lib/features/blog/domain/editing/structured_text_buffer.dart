import 'dart:convert';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// One locally recoverable, possibly invalid intermediate value. It targets
/// only an unformatted paragraph, heading or quote; no marks or links are
/// inferred, discarded or reconstructed. Empty text is intentional.
/// This is not a server document or a publishing payload.
class StructuredTextBuffer {
  StructuredTextBuffer({required this.blockId, required this.text}) {
    if (blockId.isEmpty ||
        blockId != blockId.trim() ||
        blockId.length > 2048 ||
        text.length > maxTextLength) {
      throw const FormatException('Invalid local text buffer');
    }
  }

  static const int maxTextLength = 20000;
  static const int maxEncodedLength = 150000;
  final String blockId;
  final String text;

  Map<String, Object?> toJson() => {
    'schema': 1,
    'blockId': blockId,
    'text': text,
  };
  String encode() => jsonEncode(toJson());

  static StructuredTextBuffer decode(String encoded) {
    if (encoded.length > maxEncodedLength) {
      throw const FormatException('Text buffer too large');
    }
    final value = jsonDecode(encoded);
    if (value is! Map ||
        value.length != 3 ||
        value.keys.any(
          (key) => !const {'schema', 'blockId', 'text'}.contains(key),
        ) ||
        value['schema'] is! int ||
        value['schema'] != 1 ||
        value['blockId'] is! String ||
        value['text'] is! String) {
      throw const FormatException('Invalid text buffer fields');
    }
    return StructuredTextBuffer(
      blockId: value['blockId'] as String,
      text: value['text'] as String,
    );
  }

  /// Validate the exact target without modifying the document. Buffers remain
  /// recoverable even while their text would be rejected by body validation.
  void validateTarget(StructuredArticleDraft body) {
    final matches = body.blocks.where((block) => block['id'] == blockId);
    if (matches.length != 1) {
      throw const FormatException('Missing buffer target');
    }
    final block = matches.single;
    if (!const {'paragraph', 'heading', 'quote'}.contains(block['type']) ||
        block.containsKey('inlines')) {
      throw const FormatException('Unsupported buffer target');
    }
  }

  /// Applying is explicit and still uses the existing strict body validator.
  /// On an invalid intermediate value this throws and leaves the buffer intact.
  StructuredArticleDraft applyTo(StructuredArticleDraft body) {
    validateTarget(body);
    return body.replacePlainText(blockId, text);
  }
}
