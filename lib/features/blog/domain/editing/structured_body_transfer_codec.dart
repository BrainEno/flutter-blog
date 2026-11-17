import 'dart:convert';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// A body-only, local interchange format. It is not a no-wave API request,
/// recovery-row backup, authorization, or a guarantee that linked media are
/// still available. Metadata and intermediate text buffers are not included.
///
/// The outer JSON is canonical ASCII with non-ASCII UTF-16 units represented by
/// `\\uXXXX`. This retains even unmatched surrogates without relying on a
/// clipboard or UTF-8 encoder to preserve invalid Unicode. Decode only accepts
/// the canonical form produced by this codec: duplicate keys, edited key order,
/// whitespace and noncanonical escapes are rejected, never silently repaired.
abstract final class StructuredBodyTransferCodec {
  static const format = 'nowave-local-structured-body';
  static const schema = 1;

  /// A validated body has at most one million JSON UTF-16 units. Escaping
  /// every unit into six ASCII characters plus the envelope gives this bound.
  static const maxEncodedLength = 6001000;

  static String encode(StructuredArticleDraft body) {
    final json = jsonEncode({
      'format': format,
      'schema': schema,
      'contentBlocksVersion': body.version,
      'contentBlocks': body.blocks,
    });
    final encoded = _toAscii(json);
    if (encoded.length > maxEncodedLength) {
      throw const FormatException('Structured transfer is too large');
    }
    return encoded;
  }

  /// Decode an untrusted clipboard value with an explicit bound and strict
  /// field/schema checks. Parse and re-encode before accepting so duplicate
  /// keys or alternate serialization cannot hide a different interpretation.
  /// The existing document validator then refuses unknown or damaged blocks.
  static StructuredArticleDraft decode(String encoded) {
    if (encoded.isEmpty || encoded.length > maxEncodedLength) {
      throw const FormatException('Invalid structured transfer size');
    }
    for (var i = 0; i < encoded.length; i++) {
      if (encoded.codeUnitAt(i) > 0x7f) {
        throw const FormatException('Structured transfer must be ASCII');
      }
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('Malformed structured transfer');
    }
    if (decoded is! Map ||
        decoded.length != 4 ||
        decoded.keys.any(
          (key) => !const {
            'format',
            'schema',
            'contentBlocksVersion',
            'contentBlocks',
          }.contains(key),
        ) ||
        decoded['format'] != format ||
        decoded['schema'] is! int ||
        decoded['schema'] != schema) {
      throw const FormatException('Unsupported structured transfer');
    }
    final body = StructuredArticleDraft.parse(
      version: decoded['contentBlocksVersion'],
      blocks: decoded['contentBlocks'],
    );
    if (encode(body) != encoded) {
      throw const FormatException('Noncanonical structured transfer');
    }
    return body;
  }

  static String _toAscii(String value) {
    final output = StringBuffer();
    for (final unit in value.codeUnits) {
      if (unit <= 0x7f) {
        output.writeCharCode(unit);
      } else {
        output.write(r'\u');
        output.write(unit.toRadixString(16).padLeft(4, '0'));
      }
    }
    return output.toString();
  }
}
