import 'dart:convert';

import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';

/// Decodes the known v0/v1 REST document into a read-only domain model.
/// Unsupported or malformed shapes are never mistaken for a complete body.
/// A simple v0 document retains the app's legacy Markdown interpretation.
ArticleDocument? decodeArticleDocument({
  required Object? version,
  required Object? blocks,
}) {
  final numericVersion = version is int ? version : null;
  if (numericVersion == null ||
      (numericVersion != 0 && numericVersion != 1) ||
      blocks is! List ||
      blocks.isEmpty ||
      blocks.length > 200) {
    return ArticleDocument.unsupported(numericVersion);
  }
  try {
    if (jsonEncode(blocks).length > 1000000) {
      throw const FormatException('document is too large');
    }
    final parsed = <ArticleBlock>[];
    final maps = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final value in blocks) {
      final block = _record(value);
      maps.add(block);
      final id = _text(block['id'], maxLength: 100);
      if (!seen.add(id)) throw const FormatException('duplicate block id');
      switch (block['type']) {
        case 'paragraph':
        case 'heading':
        case 'quote':
          final type = block['type'] as String;
          _fields(block, {
            'id',
            'type',
            'text',
            'inlines',
            if (type == 'heading') 'level',
            if (type == 'quote') 'attribution',
          });
          final text = _text(block['text'], maxLength: 20000);
          final runs = _runs(block, 'inlines', text, numericVersion);
          final level = block['level'];
          if (type == 'heading' && (level is! int || level < 2 || level > 4)) {
            throw const FormatException('invalid heading level');
          }
          final attribution = block['attribution'];
          if (block.containsKey('attribution') &&
              (attribution is! String || attribution.length > 300)) {
            throw const FormatException('invalid attribution');
          }
          parsed.add(
            ArticleTextBlock(
              id: id,
              kind: switch (type) {
                'heading' => ArticleTextKind.heading,
                'quote' => ArticleTextKind.quote,
                _ => ArticleTextKind.paragraph,
              },
              text: text,
              runs: runs,
              level: level is int ? level : null,
              attribution: attribution is String ? attribution : null,
            ),
          );
        case 'list':
          _fields(block, {'id', 'type', 'ordered', 'items', 'itemInlines'});
          final ordered = block['ordered'];
          final items = block['items'];
          final inlineItems = block['itemInlines'];
          if (ordered is! bool ||
              items is! List ||
              items.isEmpty ||
              items.length > 100 ||
              (block.containsKey('itemInlines') &&
                  (numericVersion != 1 ||
                      inlineItems is! List ||
                      inlineItems.length != items.length))) {
            throw const FormatException('invalid list');
          }
          parsed.add(
            ArticleListBlock(
              id: id,
              ordered: ordered,
              items: List.unmodifiable([
                for (var index = 0; index < items.length; index++)
                  _listItem(
                    items[index],
                    inlineItems is List ? inlineItems[index] : null,
                    hasInline: block.containsKey('itemInlines'),
                    version: numericVersion,
                  ),
              ]),
            ),
          );
        case 'image':
          _fields(block, {'id', 'type', 'src', 'alt', 'caption'});
          final src = _text(block['src'], maxLength: 2048);
          final alt = block['alt'];
          final caption = block['caption'];
          if (!isValidArticleResourceUrl(src) ||
              alt is! String ||
              alt.length > 1000 ||
              (block.containsKey('caption') &&
                  (caption is! String || caption.length > 1000))) {
            throw const FormatException('invalid image');
          }
          parsed.add(
            ArticleImageBlock(
              id: id,
              src: src,
              alt: alt,
              caption: caption is String ? caption : null,
            ),
          );
        case 'code':
          _fields(block, {'id', 'type', 'language', 'code'});
          final language = _text(block['language'], maxLength: 50);
          final code = block['code'];
          if (code is! String || code.length > 50000) {
            throw const FormatException('invalid code');
          }
          parsed.add(ArticleCodeBlock(id: id, language: language, code: code));
        default:
          throw const FormatException('unknown block type');
      }
    }
    if (supportsPlainEditor(version: numericVersion, blocks: maps)) {
      return null;
    }
    return ArticleDocument(
      version: numericVersion,
      blocks: List.unmodifiable(parsed),
    );
  } on FormatException {
    return ArticleDocument.unsupported(numericVersion);
  } on JsonUnsupportedObjectError {
    return ArticleDocument.unsupported(numericVersion);
  }
}

/// Encodes the original JSON, not the rendered or flattened representation.
/// The value is only cached for reading and is never sent back as an edit.
String encodeArticleDocument({
  required Object? version,
  required Object? blocks,
}) {
  try {
    final encoded = jsonEncode({'version': version, 'blocks': blocks});
    return encoded.length <= 1100000 ? encoded : '{"version":null,"blocks":[]}';
  } on JsonUnsupportedObjectError {
    return '{"version":null,"blocks":[]}';
  }
}

ArticleDocument? decodeCachedArticleDocument(String? value) {
  if (value == null) return null; // Existing cache rows are legacy Markdown.
  if (value.length > 1100000) return const ArticleDocument.unsupported(null);
  try {
    final envelope = _record(jsonDecode(value));
    return decodeArticleDocument(
      version: envelope['version'],
      blocks: envelope['blocks'],
    );
  } on FormatException {
    return const ArticleDocument.unsupported(null);
  }
}

Map<String, dynamic> _record(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('expected object');
  }
  return value.cast<String, dynamic>();
}

void _fields(Map<String, dynamic> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('unknown field');
  }
}

String _text(
  Object? value, {
  required int maxLength,
  bool allowUntrimmed = false,
}) {
  if (value is! String ||
      value.trim().isEmpty ||
      (!allowUntrimmed && value != value.trim()) ||
      value.length > maxLength) {
    throw const FormatException('invalid text');
  }
  return value;
}

ArticleListItem _listItem(
  Object? value,
  Object? inline, {
  required bool hasInline,
  required int version,
}) {
  final text = _text(value, maxLength: 2000, allowUntrimmed: true);
  return ArticleListItem(
    text: text,
    runs: hasInline
        ? _parseRuns(inline, text, version)
        : [ArticleInlineRun(text: text)],
  );
}

List<ArticleInlineRun> _runs(
  Map<String, dynamic> block,
  String key,
  String text,
  int version,
) => block.containsKey(key)
    ? _parseRuns(block[key], text, version)
    : [ArticleInlineRun(text: text)];

List<ArticleInlineRun> _parseRuns(Object? value, String expected, int version) {
  if (version != 1 || value is! List || value.isEmpty || value.length > 1000) {
    throw const FormatException('invalid inline runs');
  }
  final runs = <ArticleInlineRun>[];
  for (final raw in value) {
    final run = _record(raw);
    _fields(run, {'text', 'marks', 'href'});
    final text = run['text'];
    final href = run['href'];
    final marks = run['marks'];
    if (text is! String ||
        text.isEmpty ||
        text.length > 20000 ||
        (run.containsKey('href') &&
            (href is! String || !isValidArticleResourceUrl(href))) ||
        (run.containsKey('marks') && marks is! List)) {
      throw const FormatException('invalid inline run');
    }
    final parsedMarks = <ArticleInlineMark>{};
    if (marks is List) {
      for (final mark in marks) {
        final parsed = switch (mark) {
          'bold' => ArticleInlineMark.bold,
          'italic' => ArticleInlineMark.italic,
          'underline' => ArticleInlineMark.underline,
          'strikethrough' => ArticleInlineMark.strikethrough,
          'code' => ArticleInlineMark.code,
          _ => throw const FormatException('unknown inline mark'),
        };
        if (!parsedMarks.add(parsed)) {
          throw const FormatException('duplicate inline mark');
        }
      }
    }
    runs.add(
      ArticleInlineRun(
        text: text,
        marks: Set.unmodifiable(parsedMarks),
        href: href is String ? href : null,
      ),
    );
  }
  if (runs.map((run) => run.text).join() != expected) {
    throw const FormatException('inline text does not match fallback');
  }
  return List.unmodifiable(runs);
}
