import 'package:markdown/markdown.dart' as md;

/// A range in the visible text of a Markdown block, in UTF-16 code units.
class SpeechTextRange {
  const SpeechTextRange(this.start, this.end);
  final int start;
  final int end;
}

/// Position of spoken text inside Flutter's rendered paragraph. A WidgetSpan
/// (inline code) occupies one rendered character even when it speaks more.
class SpeechVisualRange {
  const SpeechVisualRange(
    this.start,
    this.end,
    this.visualStart, {
    this.widget = false,
  });
  final int start;
  final int end;
  final int visualStart;
  final bool widget;
}

/// One rendered title, paragraph, heading, list item, quote or code block.
class SpeechBlock {
  const SpeechBlock({
    required this.index,
    required this.text,
    required this.node,
    required this.inlineRanges,
    required this.visualRanges,
  });

  final int index;
  final String text;
  final md.Node? node;
  final Map<md.Node, SpeechTextRange> inlineRanges;
  final List<SpeechVisualRange> visualRanges;

  int visualOffset(int spokenOffset) {
    for (final range in visualRanges) {
      if (spokenOffset >= range.start && spokenOffset < range.end) {
        return range.visualStart +
            (range.widget ? 0 : spokenOffset - range.start);
      }
    }
    if (visualRanges.isEmpty) return 0;
    final last = visualRanges.last;
    return last.visualStart + (last.widget ? 0 : last.end - last.start);
  }
}

/// A bounded utterance and its position in the original rendered block.
class SpeechChunk {
  const SpeechChunk({
    required this.text,
    required this.blockIndex,
    required this.blockOffset,
    required this.start,
  });

  final String text;
  final int blockIndex;
  final int blockOffset;

  /// Offset in the concatenation of utterances (excluding block separators).
  final int start;
}

/// A tight Markdown list item may contain consecutive inline nodes instead
/// of a paragraph node. Group them exactly as the reader renders them, while
/// retaining the first AST node as a stable owner for follow highlighting.
class MarkdownListPart {
  const MarkdownListPart(this.owner, this.inline);
  final md.Node owner;
  final List<md.Node>? inline;
}

Iterable<MarkdownListPart> markdownListParts(md.Element item) sync* {
  const blocks = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'hr',
    'blockquote',
    'ul',
    'ol',
  };
  var inline = <md.Node>[];
  for (final child in item.children ?? const <md.Node>[]) {
    if (child is md.Element && blocks.contains(child.tag)) {
      if (inline.isNotEmpty) {
        yield MarkdownListPart(inline.first, inline);
        inline = <md.Node>[];
      }
      yield MarkdownListPart(child, null);
    } else {
      inline.add(child);
    }
  }
  if (inline.isNotEmpty) yield MarkdownListPart(inline.first, inline);
}

/// Existing Markdown code remains trimmed; server code blocks can explicitly
/// opt into preserving the exact whitespace supplied by the author.
String markdownCodeText(md.Element node) =>
    node.attributes['data-preserve-whitespace'] == 'true'
    ? node.textContent
    : node.textContent.trim();

/// The same Markdown AST drives both rendering and narration. Visible code
/// is included; link targets, controls, images and media URLs are not spoken.
class ReadAloudDocument {
  ReadAloudDocument._(this.nodes, this.blocks, this.chunks, this.blockByNode);

  final List<md.Node> nodes;
  final List<SpeechBlock> blocks;
  final List<SpeechChunk> chunks;
  final Map<md.Node, SpeechBlock> blockByNode;

  int get totalLength =>
      chunks.isEmpty ? 0 : chunks.last.start + chunks.last.text.length;

  /// Match the reference reader: do not offer narration for an empty body.
  bool get hasBody =>
      blocks.skip(1).any((block) => block.text.trim().isNotEmpty);

  factory ReadAloudDocument.parse(String title, String markdown) {
    List<md.Node> nodes;
    try {
      nodes = md.Document().parseLines(markdown.split('\n'));
    } catch (_) {
      // Keep a malformed article from taking down the reader.
      nodes = const [];
    }
    return ReadAloudDocument.fromNodes(title, nodes);
  }

  /// Reuse one already-built AST for display, text offsets and speech.
  factory ReadAloudDocument.fromNodes(String title, List<md.Node> nodes) {
    final blocks = <SpeechBlock>[
      SpeechBlock(
        index: 0,
        text: title,
        node: null,
        inlineRanges: const {},
        visualRanges: [SpeechVisualRange(0, title.length, 0)],
      ),
    ];
    final blockByNode = <md.Node, SpeechBlock>{};

    void addBlock(md.Node owner, List<md.Node> inline, {bool code = false}) {
      final text = StringBuffer();
      final ranges = <md.Node, SpeechTextRange>{};
      final visualRanges = <SpeechVisualRange>[];
      var visualOffset = 0;

      void append(md.Node node, String value, {bool widget = false}) {
        final start = text.length;
        text.write(value);
        ranges[node] = SpeechTextRange(start, text.length);
        if (value.isNotEmpty) {
          visualRanges.add(
            SpeechVisualRange(start, text.length, visualOffset, widget: widget),
          );
        }
        visualOffset += widget ? 1 : value.length;
      }

      void walkInline(md.Node node) {
        if (node is md.Text) {
          append(node, node.text);
          return;
        }
        if (node is! md.Element) {
          append(node, node.textContent);
          return;
        }
        switch (node.tag) {
          case 'script':
          case 'style':
          case 'iframe':
          case 'audio':
          case 'video':
          case 'input':
          case 'annotation':
            visualOffset += node.textContent.length;
            return;
          case 'img':
            visualOffset++; // A WidgetSpan, even when the URL is rejected.
            return;
          case 'br':
            append(node, '\n');
            return;
          case 'code':
            append(node, node.textContent, widget: true);
            return;
          default:
            for (final child in node.children ?? const <md.Node>[]) {
              walkInline(child);
            }
        }
      }

      if (code && owner is md.Element) {
        append(owner, markdownCodeText(owner));
      } else {
        for (final node in inline) {
          walkInline(node);
        }
      }
      final value = text.toString();
      if (value.trim().isEmpty) return;
      final block = SpeechBlock(
        index: blocks.length,
        text: value,
        node: owner,
        inlineRanges: Map.unmodifiable(ranges),
        visualRanges: List.unmodifiable(visualRanges),
      );
      blocks.add(block);
      blockByNode[owner] = block;
    }

    void walkBlock(md.Node node) {
      if (node is! md.Element) {
        addBlock(node, [node]);
        return;
      }
      switch (node.tag) {
        case 'hr':
          return;
        case 'blockquote':
        case 'ul':
        case 'ol':
          for (final child in node.children ?? const <md.Node>[]) {
            walkBlock(child);
          }
          return;
        case 'li':
          for (final part in markdownListParts(node)) {
            final inline = part.inline;
            if (inline == null) {
              walkBlock(part.owner);
            } else {
              addBlock(part.owner, inline);
            }
          }
          return;
        case 'pre':
          addBlock(node, const [], code: true);
          return;
        case 'p':
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          addBlock(node, node.children ?? const []);
          return;
        default:
          addBlock(node, [node]);
      }
    }

    for (final node in nodes) {
      walkBlock(node);
    }

    final chunks = <SpeechChunk>[];
    var total = 0;
    for (final block in blocks) {
      for (final part in _splitBlock(block.text)) {
        chunks.add(
          SpeechChunk(
            text: part.text,
            blockIndex: block.index,
            blockOffset: part.offset,
            start: total,
          ),
        );
        total += part.text.length;
      }
    }
    return ReadAloudDocument._(
      List.unmodifiable(nodes),
      List.unmodifiable(blocks),
      List.unmodifiable(chunks),
      Map.unmodifiable(blockByNode),
    );
  }
}

class _BlockPart {
  const _BlockPart(this.text, this.offset);
  final String text;
  final int offset;
}

/// Use at most 220 Unicode scalar values per utterance, preferring a sentence
/// or word boundary in the second half. Offsets remain UTF-16 for native APIs.
Iterable<_BlockPart> _splitBlock(String text, {int maxLength = 220}) sync* {
  for (final match in RegExp(r'[^\n]+').allMatches(text)) {
    final paragraph = match.group(0)!;
    final runes = paragraph.runes.toList(growable: false);
    final offsets = <int>[0];
    for (final rune in runes) {
      offsets.add(offsets.last + (rune > 0xffff ? 2 : 1));
    }
    var first = 0;
    while (first < runes.length) {
      var end = (first + maxLength).clamp(0, runes.length);
      if (end < runes.length) {
        for (var i = end - 1; i >= first + maxLength ~/ 2; i--) {
          if (RegExp(r'[。！？.!?；;\s]').hasMatch(String.fromCharCode(runes[i]))) {
            end = i + 1;
            break;
          }
        }
      }
      final raw = paragraph.substring(offsets[first], offsets[end]);
      final trimmedLeft = raw.trimLeft();
      final trimmed = trimmedLeft.trimRight();
      if (trimmed.isNotEmpty) {
        yield _BlockPart(
          trimmed,
          match.start + offsets[first] + raw.length - trimmedLeft.length,
        );
      }
      first = end;
    }
  }
}

/// Select Chinese or English from each passage, independent of the UI locale.
String speechLanguage(String text, String fallback) {
  var han = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x3400 && rune <= 0x9fff) ||
        (rune >= 0xf900 && rune <= 0xfaff) ||
        (rune >= 0x20000 && rune <= 0x323af)) {
      han++;
    } else if ((rune >= 0x41 && rune <= 0x5a) ||
        (rune >= 0x61 && rune <= 0x7a) ||
        (rune >= 0x00c0 && rune <= 0x024f) ||
        (rune >= 0x1e00 && rune <= 0x1eff)) {
      latin++;
    }
  }
  if (han != 0 || latin != 0) return han * 2 >= latin ? 'zh-CN' : 'en';
  return fallback;
}

/// Clamp a native UTF-16 boundary without splitting a surrogate pair.
int speechCodePointBoundary(String text, int desired, {bool end = false}) {
  var offset = desired.clamp(0, text.length);
  if (offset > 0 && offset < text.length) {
    final current = text.codeUnitAt(offset);
    final previous = text.codeUnitAt(offset - 1);
    if (current >= 0xdc00 &&
        current <= 0xdfff &&
        previous >= 0xd800 &&
        previous <= 0xdbff) {
      offset += end ? 1 : -1;
    }
  }
  return offset;
}

/// Snap a seek to a whole Latin word and never split a UTF-16 surrogate pair.
int safeSpeechOffset(String text, int desired) {
  var offset = speechCodePointBoundary(text, desired);
  bool word(int unit) =>
      (unit >= 0x41 && unit <= 0x5a) ||
      (unit >= 0x61 && unit <= 0x7a) ||
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0xc0 && unit <= 0x024f) ||
      unit == 0x27 ||
      unit == 0x2019 ||
      unit == 0x2d;
  if (offset > 0 &&
      offset < text.length &&
      word(text.codeUnitAt(offset)) &&
      word(text.codeUnitAt(offset - 1))) {
    while (offset > 0 && word(text.codeUnitAt(offset - 1))) {
      offset--;
    }
  }
  return offset;
}
