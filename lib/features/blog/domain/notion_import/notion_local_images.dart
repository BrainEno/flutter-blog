import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/features/blog/domain/notion_import/notion_import.dart';

/// An image file inside a Notion export, or chosen beside its pages. Its
/// bytes are read only when a chosen page that uses it is previewed.
class NotionLocalImage {
  NotionLocalImage({
    required this.name,
    required this.size,
    required Uint8List Function() read,
  }) : _read = read;

  /// The path inside the export, or the chosen file's name.
  final String name;

  /// The size the export declares; [read] checks it.
  final int size;
  final Uint8List Function() _read;

  /// The image bytes. Throws a `NotionImportSourceException` when the
  /// archive is damaged or the image is larger than an upload may be.
  Uint8List read() => _read();
}

/// A local image stands in a converted page as an `external` image whose
/// address uses this scheme. It never leaves the device: before a preview
/// the app uploads the image and puts the media address in its place, or
/// takes the block out. The server would refuse the scheme in any case.
const notionLocalImageScheme = 'nowave-local-image';

/// Image files an export can contain. Only [notionUploadableImageType]
/// formats can be uploaded; the rest are named so a page that uses one says
/// why its image is missing rather than that it was not found.
bool isNotionImageFileName(String name) => RegExp(
  r'\.(png|jpe?g|webp|gif|heic|heif|svg|bmp|tiff?|avif)$',
  caseSensitive: false,
).hasMatch(name);

/// Whether the media service takes this file, judged by its name.
bool isNotionUploadableImageName(String name) =>
    RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(name);

/// The content type of JPEG, PNG and WebP bytes - the three the media
/// service accepts - from their signature, not their name: an export can
/// hold a misnamed file. Null for anything else.
String? notionUploadableImageType(Uint8List bytes) {
  bool starts(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (starts(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) {
    return 'image/webp';
  }
  return null;
}

String notionLocalImageUrl(String key) =>
    '$notionLocalImageScheme:${Uri.encodeComponent(key)}';

/// The local image an image block stands for, or null for any other block.
String? notionLocalImageKey(Object? block) {
  if (block is! Map || block['type'] != 'image') return null;
  final image = block['image'];
  if (image is! Map || image['type'] != 'external') return null;
  final external = image['external'];
  final url = external is Map ? external['url'] : null;
  const prefix = '$notionLocalImageScheme:';
  if (url is! String || !url.startsWith(prefix)) return null;
  try {
    return Uri.decodeComponent(url.substring(prefix.length));
  } on ArgumentError {
    return null;
  }
}

/// The local images [bundle]'s pages use, in first-use order.
List<String> notionLocalImageKeys(NotionBundle bundle) {
  final keys = <String>{};
  for (final page in bundle.json['pages'] as List) {
    for (final block in (page as Map)['blocks'] as List) {
      final key = notionLocalImageKey(block);
      if (key != null) keys.add(key);
    }
  }
  return keys.toList();
}

/// [bundle] with each local image replaced by its uploaded address, or
/// taken out when [urls] has no address for it. Every other byte of the
/// bundle is kept as it was.
NotionBundle withNotionLocalImages(
  NotionBundle bundle,
  Map<String, String> urls,
) {
  List<dynamic> blocks(List<dynamic> source) {
    final out = <dynamic>[];
    for (final block in source) {
      final key = notionLocalImageKey(block);
      if (key == null) {
        out.add(block);
        continue;
      }
      final url = urls[key];
      if (url == null) continue;
      final map = block as Map<String, dynamic>;
      out.add({
        ...map,
        'image': {
          ...(map['image'] as Map<String, dynamic>),
          'external': {'url': url},
        },
      });
    }
    return out;
  }

  final json = bundle.json;
  return NotionBundle.parse(
    jsonEncode({
      ...json,
      'pages': [
        for (final page in json['pages'] as List)
          {
            ...(page as Map<String, dynamic>),
            'blocks': blocks(page['blocks'] as List),
          },
      ],
    }),
  );
}
