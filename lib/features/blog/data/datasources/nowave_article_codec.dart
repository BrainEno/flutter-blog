import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:uuid/uuid.dart';

/// Codec between the app's plain-text article body and the no-wave
/// `contentBlocks` document (version 0: plain text, no inline marks).
///
/// The server contract (verified against `apps/api/src/domain/article.ts`):
/// - 1-200 blocks, every block carries a unique `id` (1-100 chars),
/// - `paragraph`/`heading`/`quote` need non-empty `text` (<= 20000 chars),
/// - `image` needs `src` (site-relative or http(s), <= 2048) and a string
///   `alt` (<= 1000),
/// - unknown fields are rejected.
///
/// Mapping rules for this app:
/// - the article body's blank-line-separated passages become `paragraph`
///   blocks (internal single newlines are preserved inside a block),
/// - the cover image becomes the leading `image` block; on the way back
///   the first image block is the cover and every other block contributes
///   plain text.

/// Result of flattening content blocks back into the app's model.
class ExtractedBlogContent {
  const ExtractedBlogContent({required this.content, required this.coverUrl});

  final String content;
  final String coverUrl;
}

const int _kMaxBlockTextLength = 20000;

/// Whether the current plain editor can rebuild the server's body without
/// dropping structured block types, inline formatting or image metadata.
/// Unknown versions and shapes fail closed. Block IDs are regenerated when
/// writing; this check does not provide concurrent edit detection.
bool supportsPlainEditor({
  required Object? version,
  required List<Map<String, dynamic>> blocks,
}) {
  if (version is! int || version != 0 || blocks.isEmpty) return false;
  var hasParagraph = false;
  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    if (block['type'] == 'paragraph') {
      const allowed = {'id', 'type', 'text'};
      final text = block['text'];
      if (block.keys.any((key) => !allowed.contains(key)) ||
          text is! String ||
          text.isEmpty ||
          text != text.trim() ||
          RegExp(r'\n[ \t]*\n').hasMatch(text)) {
        return false;
      }
      hasParagraph = true;
    } else if (block['type'] == 'image') {
      const allowed = {'id', 'type', 'src', 'alt', 'caption'};
      if (index != 0 ||
          block.keys.any((key) => !allowed.contains(key)) ||
          block['src'] is! String ||
          (block['src'] as String).isEmpty ||
          block['alt'] != '' ||
          (block['caption'] != null && block['caption'] != '')) {
        return false;
      }
    } else {
      return false;
    }
  }
  return hasParagraph;
}

/// Splits the plain-text body into paragraphs, bounding each block below
/// the server's per-block text limit.
List<String> splitContentParagraphs(String content) {
  final passages = content
      .split(RegExp(r'\n[ \t]*\n'))
      .map((passage) => passage.trim())
      .where((passage) => passage.isNotEmpty)
      .toList();
  if (passages.isEmpty) return const [];

  final bounded = <String>[];
  for (final passage in passages) {
    if (passage.length <= _kMaxBlockTextLength) {
      bounded.add(passage);
      continue;
    }
    // Over the limit: fall back to splitting on single newlines, then hard
    // chunk whatever remains. Such input is far outside anything the
    // editor produces, but it must not crash.
    final lines = passage.split('\n');
    final buffer = StringBuffer();
    for (final line in lines) {
      if (buffer.isNotEmpty &&
          buffer.length + 1 + line.length > _kMaxBlockTextLength) {
        bounded.add(buffer.toString());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(line);
    }
    if (buffer.isNotEmpty) bounded.add(buffer.toString());
  }
  // Hard-chunk anything still over the limit (a single very long line).
  if (bounded.any((block) => block.length > _kMaxBlockTextLength)) {
    final result = <String>[];
    for (final block in bounded) {
      for (var start = 0; start < block.length; start += _kMaxBlockTextLength) {
        final end = (start + _kMaxBlockTextLength) < block.length
            ? start + _kMaxBlockTextLength
            : block.length;
        result.add(block.substring(start, end));
      }
    }
    return result;
  }
  return bounded;
}

/// Builds the contentBlocks document for an upload/update.
///
/// [coverUrl] is the immutable media URL of the freshly uploaded cover, or
/// null when the article has no cover. Throws a validation [ServerException]
/// when the body has no publishable text.
List<Map<String, dynamic>> blogToContentBlocks({
  required String content,
  String? coverUrl,
}) {
  final paragraphs = splitContentParagraphs(content);
  if (paragraphs.isEmpty) {
    throw const ServerException(
      '正文不能为空',
      kind: FailureKind.validation,
      code: 'article.emptyBody',
    );
  }
  final uuid = const Uuid();
  final blocks = <Map<String, dynamic>>[
    if (coverUrl != null && coverUrl.isNotEmpty)
      <String, dynamic>{
        'id': uuid.v4(),
        'type': 'image',
        'src': coverUrl,
        'alt': '',
      },
    for (final paragraph in paragraphs)
      <String, dynamic>{
        'id': uuid.v4(),
        'type': 'paragraph',
        'text': paragraph,
      },
  ];
  return blocks;
}

/// Flattens a contentBlocks document back into the app's plain-text body
/// and picks the first image block as the cover.
ExtractedBlogContent extractBlogContent(List<Map<String, dynamic>> blocks) {
  final coverUrl = blocks
      .where((block) => block['type'] == 'image')
      .map((block) => block['src'] is String ? block['src'] as String : '')
      .firstWhere((src) => src.isNotEmpty, orElse: () => '');

  final parts = <String>[];
  for (final block in blocks) {
    switch (block['type']) {
      case 'paragraph':
      case 'heading':
      case 'quote':
        final rawText = block['text'];
        final text = rawText is String ? rawText.trim() : '';
        if (text.isNotEmpty) parts.add(text);
      case 'list':
        final rawItems = block['items'];
        final items = (rawItems is List ? rawItems : const [])
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty);
        if (items.isNotEmpty) parts.add(items.join('\n'));
      case 'code':
        final rawCode = block['code'];
        final code = rawCode is String ? rawCode.trim() : '';
        if (code.isNotEmpty) parts.add(code);
      case 'image':
        // The first image is the cover; later ones degrade to captions.
        final rawCaption = block['caption'];
        final caption = rawCaption is String ? rawCaption.trim() : '';
        if (caption.isNotEmpty) parts.add(caption);
      default:
        break;
    }
  }
  return ExtractedBlogContent(content: parts.join('\n\n'), coverUrl: coverUrl);
}
