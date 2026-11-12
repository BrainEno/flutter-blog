import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/utils/article_resource_url.dart';

/// A known taxonomy selection and whether the author changed it. Null at the
/// metadata level means unknown, not an empty or untouched selection.
class StructuredTaxonomySelection {
  StructuredTaxonomySelection({
    required List<String> values,
    required this.touched,
  }) : values = List.unmodifiable(values) {
    if (values.length > 100 || values.any((value) => value.length > 2048)) {
      throw const FormatException('Invalid taxonomy selection');
    }
  }

  final List<String> values;
  final bool touched;

  Map<String, Object?> toJson() => {'values': values, 'touched': touched};

  static StructuredTaxonomySelection? parse(Object? value) {
    if (value == null) return null;
    final map = _record(value, {'values', 'touched'});
    final values = map['values'];
    final touched = map['touched'];
    if (values is! List ||
        values.any((item) => item is! String) ||
        touched is! bool) {
      throw const FormatException('Invalid taxonomy selection');
    }
    return StructuredTaxonomySelection(
      values: values.cast<String>(),
      touched: touched,
    );
  }
}

/// A cover selection, kept separately from the article's image blocks.
/// Local bytes are copied into the recovery snapshot, not a temporary picker
/// path. Validation checks bounds and MIME, not image decoding or server upload.
enum StructuredCoverKind { unchanged, removed, remote, local }

class StructuredCoverSelection {
  StructuredCoverSelection._(
    this.kind,
    this.url,
    this.mimeType,
    List<int>? bytes,
  ) : _bytes = bytes == null
          ? null
          : Uint8List.fromList(bytes).asUnmodifiableView();

  factory StructuredCoverSelection.unchanged() => StructuredCoverSelection._(
    StructuredCoverKind.unchanged,
    null,
    null,
    null,
  );

  factory StructuredCoverSelection.removed() =>
      StructuredCoverSelection._(StructuredCoverKind.removed, null, null, null);

  factory StructuredCoverSelection.remote(String url) {
    if (!isValidArticleResourceUrl(url)) {
      throw const FormatException('Invalid cover URL');
    }
    return StructuredCoverSelection._(
      StructuredCoverKind.remote,
      url,
      null,
      null,
    );
  }

  factory StructuredCoverSelection.local({
    required String mimeType,
    required List<int> bytes,
  }) {
    if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType) ||
        bytes.isEmpty ||
        bytes.length > maxImageBytes ||
        bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid local cover');
    }
    return StructuredCoverSelection._(
      StructuredCoverKind.local,
      null,
      mimeType,
      bytes,
    );
  }

  /// no-wave's REST image upload limit at the audited upstream revision.
  static const int maxImageBytes = 8 * 1024 * 1024;
  final StructuredCoverKind kind;
  final String? url;
  final String? mimeType;
  final Uint8List? _bytes;
  late final String? _checksum = switch (_bytes) {
    final Uint8List value => _crc32(value),
    null => null,
  };

  /// A detached copy; callers cannot mutate a saved selection through it.
  Uint8List? get bytes => switch (_bytes) {
    final Uint8List value => Uint8List.fromList(value),
    null => null,
  };

  Map<String, Object?> toJson() => switch (kind) {
    StructuredCoverKind.unchanged => {'kind': 'unchanged'},
    StructuredCoverKind.removed => {'kind': 'removed'},
    StructuredCoverKind.remote => {'kind': 'remote', 'url': url},
    StructuredCoverKind.local => _localJson(),
  };

  Map<String, Object?> _localJson() {
    final value = _bytes;
    if (value == null) throw StateError('Missing local cover bytes');
    return {
      'kind': 'local',
      'mimeType': mimeType,
      'bytes': base64Encode(value),
      'byteLength': value.length,
      'crc32': _checksum,
    };
  }

  static StructuredCoverSelection? parse(Object? value) {
    if (value == null) return null;
    if (value is! Map || value['kind'] is! String) {
      throw const FormatException('Invalid cover');
    }
    switch (value['kind']) {
      case 'unchanged':
        _record(value, {'kind'});
        return StructuredCoverSelection.unchanged();
      case 'removed':
        _record(value, {'kind'});
        return StructuredCoverSelection.removed();
      case 'remote':
        final map = _record(value, {'kind', 'url'});
        if (map['url'] is! String) {
          throw const FormatException('Invalid cover URL');
        }
        return StructuredCoverSelection.remote(map['url'] as String);
      case 'local':
        final map = _record(value, {
          'kind',
          'mimeType',
          'bytes',
          'byteLength',
          'crc32',
        });
        final mime = map['mimeType'];
        final bytes = map['bytes'];
        final byteLength = map['byteLength'];
        final checksum = map['crc32'];
        if (mime is! String ||
            bytes is! String ||
            byteLength is! int ||
            byteLength < 1 ||
            byteLength > maxImageBytes ||
            checksum is! String ||
            bytes.length > maxEncodedImageLength) {
          throw const FormatException('Invalid local cover');
        }
        final decoded = base64Decode(bytes);
        if (base64Encode(decoded) != bytes ||
            decoded.length != byteLength ||
            _crc32(decoded) != checksum) {
          throw const FormatException('Invalid cover encoding or checksum');
        }
        return StructuredCoverSelection.local(mimeType: mime, bytes: decoded);
      default:
        throw const FormatException('Unknown cover kind');
    }
  }

  static const int maxEncodedImageLength = ((maxImageBytes + 2) ~/ 3) * 4;
}

/// Local editor metadata. Null means unknown, including for publication state;
/// empty text and empty selections are retained as deliberate input. This is a
/// recovery representation, not a valid server request or authorization.
class StructuredSessionMetadata {
  StructuredSessionMetadata({
    required this.slug,
    required this.title,
    required this.summary,
    required this.workType,
    required this.publicationState,
    required this.tags,
    required this.categories,
    required this.cover,
  }) {
    for (final text in [slug, title, summary, workType]) {
      if (text != null && text.length > 20000) {
        throw const FormatException('Metadata text is too large');
      }
    }
    if (publicationState != null &&
        publicationState != 'draft' &&
        publicationState != 'published') {
      throw const FormatException('Unknown publication state');
    }
    if (jsonEncode(toJson()).length > maxEncodedLength) {
      throw const FormatException('Metadata is too large');
    }
  }

  /// Overall cap includes an 8 MiB base64 cover plus bounded text and lists.
  static const int maxEncodedLength = 12 * 1024 * 1024;
  final String? slug;
  final String? title;
  final String? summary;
  final String? workType;
  final String? publicationState;

  /// Tag names as shown by the editor, not resolved server tag IDs.
  final StructuredTaxonomySelection? tags;

  /// Category IDs, never category names or slugs.
  final StructuredTaxonomySelection? categories;
  final StructuredCoverSelection? cover;

  Map<String, Object?> toJson() => {
    'schema': 1,
    'slug': slug,
    'title': title,
    'summary': summary,
    'workType': workType,
    'publicationState': publicationState,
    'tags': tags?.toJson(),
    'categories': categories?.toJson(),
    'cover': cover?.toJson(),
  };

  static StructuredSessionMetadata parse(Object? value) {
    final map = _record(value, {
      'schema',
      'slug',
      'title',
      'summary',
      'workType',
      'publicationState',
      'tags',
      'categories',
      'cover',
    });
    if (map['schema'] != 1 || map['schema'] is! int) {
      throw const FormatException('Unknown metadata version');
    }
    return StructuredSessionMetadata(
      slug: _nullableText(map['slug']),
      title: _nullableText(map['title']),
      summary: _nullableText(map['summary']),
      workType: _nullableText(map['workType']),
      publicationState: _nullableText(map['publicationState']),
      tags: StructuredTaxonomySelection.parse(map['tags']),
      categories: StructuredTaxonomySelection.parse(map['categories']),
      cover: StructuredCoverSelection.parse(map['cover']),
    );
  }

  static StructuredSessionMetadata decode(String encoded) {
    if (encoded.length > maxEncodedLength) {
      throw const FormatException('Metadata is too large');
    }
    return parse(jsonDecode(encoded));
  }
}

Map<String, Object?> _record(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    throw const FormatException('Invalid metadata fields');
  }
  return value.cast<String, Object?>();
}

String? _nullableText(Object? value) {
  if (value != null && value is! String) {
    throw const FormatException('Invalid metadata text');
  }
  return value as String?;
}

/// Detects common accidental damage, not malicious tampering or a valid image.
final List<int> _crcTable = List.unmodifiable(
  List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
    return crc;
  }),
);

String _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}
