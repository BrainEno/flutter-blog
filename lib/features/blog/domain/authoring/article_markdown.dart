import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';

/// The article body as the traditional editor shows it: one Markdown text
/// plus the cover, which the editor keeps in its own field.
///
/// The Markdown is a small, fixed dialect that maps one-to-one onto the
/// no-wave document blocks, so what the author types is exactly what is
/// published - on the web as well as in the app:
///
/// | Markdown                         | no-wave block / mark        |
/// |----------------------------------|-----------------------------|
/// | blank-line separated text        | `paragraph`                 |
/// | `## ` / `### ` / `#### `         | `heading` level 2-4         |
/// | `> ` lines                       | `quote`                     |
/// | `- ` / `1. ` lines               | `list` (bulleted / ordered) |
/// | ```` ```lang ```` fenced lines   | `code` (`text` by default)  |
/// | `![alt](src "caption")` alone    | `image`                     |
/// | `**b**` `*i*` `~~s~~` `<u>u</u>` | bold, italic, strike, under |
/// | `` `code` `` `[text](url)`       | inline code, link           |
///
/// A backslash escapes any ASCII punctuation, which is how literal `*` or `#`
/// survive. A single `#` heading becomes level 2: the article title is the
/// level 1 and lives in its own field, as on the web.
class EditableArticleBody {
  const EditableArticleBody({required this.markdown, this.coverUrl = ''});

  final String markdown;

  /// The leading cover image, or empty when the article has none.
  final String coverUrl;
}

/// The code language written when a fence names none - the web editor's.
const String articleDefaultCodeLanguage = 'text';

const int _maxListItems = 100;
const int _maxCodeLanguageLength = 50;

/// The body of [document] as editable Markdown, or null when it cannot be
/// represented without loss.
///
/// The answer is proven, not assumed: the rendered text is parsed back and
/// must give the same blocks (ids aside). Anything else - a quote with an
/// attribution, a heading with a line break, an unknown document - fails
/// closed, so saving from the editor can never flatten an article.
EditableArticleBody? editableBodyOf(ArticleDocument document) {
  if (!document.supported) return null;
  var blocks = document.blocks;
  var coverUrl = '';
  final first = blocks.isEmpty ? null : blocks.first;
  if (first is ArticleImageBlock &&
      first.alt.isEmpty &&
      (first.caption ?? '').isEmpty) {
    coverUrl = first.src;
    blocks = blocks.sublist(1);
  }
  for (final block in blocks) {
    if (block is ArticleTextBlock && (block.attribution ?? '').isNotEmpty) {
      return null;
    }
  }
  final markdown = renderArticleMarkdown(blocks);
  if (!sameArticleBlocks(blocks, parseArticleMarkdown(markdown))) return null;
  return EditableArticleBody(markdown: markdown, coverUrl: coverUrl);
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

final _fenceOpen = RegExp(r'^(`{3,}|~{3,})[ \t]*([^\s`]*)[ \t]*$');
final _heading = RegExp(r'^(#{1,6})[ \t]+(.*\S.*)$');
// Item lines inside a list; an empty item is allowed and dropped.
final _bullet = RegExp(r'^[-*+](?:[ \t]+(.*))?$');
final _ordered = RegExp(r'^(\d{1,9})[.)](?:[ \t]+(.*))?$');
// A list only starts at a marker followed by text, so a lone `-` stays text.
final _bulletStart = RegExp(r'^[-*+][ \t]+\S');
final _orderedStart = RegExp(r'^\d{1,9}[.)][ \t]+\S');
// What rendering must escape: anything an item line could be read as.
final _bulletEscape = RegExp(r'^[-*+](?:[ \t]|$)');
final _orderedEscape = RegExp(r'^\d{1,9}[.)](?:[ \t]|$)');
final _image = RegExp(
  r'^!\[((?:\\.|[^\\\]])*)\]\([ \t]*(<[^<>\n]*>|[^\s()<>]+)'
  r'(?:[ \t]+"((?:\\.|[^\\"])*)")?[ \t]*\)$',
);

/// Parses the editor's Markdown into document blocks. Block ids are empty:
/// the data layer assigns fresh ones when it writes.
List<ArticleBlock> parseArticleMarkdown(String source) {
  final lines = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks = <ArticleBlock>[];
  var index = 0;
  while (index < lines.length) {
    final line = lines[index].trimLeft();
    if (line.isEmpty) {
      index++;
      continue;
    }

    final fence = _fenceOpen.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      var language = fence.group(2)!;
      if (language.isEmpty) language = articleDefaultCodeLanguage;
      if (language.length > _maxCodeLanguageLength) {
        language = language.substring(0, _maxCodeLanguageLength);
      }
      final code = <String>[];
      index++;
      while (index < lines.length && !_closesFence(lines[index], marker)) {
        code.add(lines[index]);
        index++;
      }
      if (index < lines.length) index++;
      blocks.add(
        ArticleCodeBlock(id: '', language: language, code: code.join('\n')),
      );
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final text = heading.group(2)!.trim();
      final level = heading.group(1)!.length.clamp(2, 4);
      blocks.add(_textBlock(ArticleTextKind.heading, text, level: level));
      index++;
      continue;
    }

    if (line.startsWith('>')) {
      final quoted = <String>[];
      while (index < lines.length && lines[index].trimLeft().startsWith('>')) {
        quoted.add(_stripQuote(lines[index].trimLeft()));
        index++;
      }
      final text = quoted.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(_textBlock(ArticleTextKind.quote, text));
      }
      continue;
    }

    final image = _imageOf(line);
    if (image != null) {
      blocks.add(image);
      index++;
      continue;
    }

    final listKind = _listKind(line);
    if (listKind != null) {
      index = _parseList(lines, index, listKind == _ListKind.ordered, blocks);
      continue;
    }

    final paragraph = <String>[];
    while (index < lines.length) {
      final current = lines[index];
      final trimmed = current.trimLeft();
      if (trimmed.isEmpty ||
          (paragraph.isNotEmpty && _interruptsParagraph(trimmed))) {
        break;
      }
      paragraph.add(current);
      index++;
    }
    final text = paragraph.join('\n').trim();
    if (text.isNotEmpty) {
      blocks.add(_textBlock(ArticleTextKind.paragraph, text));
    }
  }
  return blocks;
}

enum _ListKind { bullet, ordered }

_ListKind? _listKind(String trimmed) {
  if (_bulletStart.hasMatch(trimmed)) return _ListKind.bullet;
  if (_orderedStart.hasMatch(trimmed)) return _ListKind.ordered;
  return null;
}

String? _listItemText(String trimmed, bool ordered) {
  final match = (ordered ? _ordered : _bullet).firstMatch(trimmed);
  if (match == null) return null;
  return match.group(ordered ? 2 : 1) ?? '';
}

/// Reads one list starting at [start] and returns the index after it.
///
/// Items of the same kind continue the list across blank lines, so typing a
/// numbered list with spaces between items still numbers 1, 2, 3. A plain
/// line right below an item continues that item.
int _parseList(
  List<String> lines,
  int start,
  bool ordered,
  List<ArticleBlock> blocks,
) {
  final items = <String>[];
  var index = start;
  while (index < lines.length) {
    final trimmed = lines[index].trimLeft();
    if (trimmed.isEmpty) {
      var next = index + 1;
      while (next < lines.length && lines[next].trim().isEmpty) {
        next++;
      }
      if (next < lines.length &&
          _listKind(lines[next].trimLeft()) ==
              (ordered ? _ListKind.ordered : _ListKind.bullet)) {
        index = next;
        continue;
      }
      break;
    }
    final item = _listItemText(trimmed, ordered);
    if (item != null) {
      items.add(item);
      index++;
      continue;
    }
    if (_bullet.hasMatch(trimmed) ||
        _ordered.hasMatch(trimmed) ||
        _interruptsParagraph(trimmed) ||
        items.isEmpty) {
      break;
    }
    items[items.length - 1] = '${items.last}\n$trimmed';
    index++;
  }
  final kept = [
    for (final item in items)
      if (item.trim().isNotEmpty) item.trim(),
  ];
  for (var from = 0; from < kept.length; from += _maxListItems) {
    final chunk = kept.sublist(
      from,
      from + _maxListItems < kept.length ? from + _maxListItems : kept.length,
    );
    blocks.add(
      ArticleListBlock(
        id: '',
        ordered: ordered,
        items: List.unmodifiable([
          for (final item in chunk)
            ArticleListItem(text: _plainOf(item), runs: parseInlineRuns(item)),
        ]),
      ),
    );
  }
  return index;
}

/// Whether [trimmed] starts a new block even straight after a text line.
/// Only `1.` interrupts a paragraph, so "2024. That year" stays text.
bool _interruptsParagraph(String trimmed) {
  if (_fenceOpen.hasMatch(trimmed) ||
      _heading.hasMatch(trimmed) ||
      trimmed.startsWith('>') ||
      _bulletStart.hasMatch(trimmed) ||
      _imageOf(trimmed) != null) {
    return true;
  }
  final ordered = _ordered.firstMatch(trimmed);
  return ordered != null &&
      _orderedStart.hasMatch(trimmed) &&
      int.parse(ordered.group(1)!) == 1;
}

bool _closesFence(String line, String marker) {
  final trimmed = line.trim();
  return trimmed.length >= marker.length &&
      trimmed.split('').every((char) => char == marker[0]);
}

String _stripQuote(String trimmed) {
  final rest = trimmed.substring(1);
  return rest.startsWith(' ') || rest.startsWith('\t')
      ? rest.substring(1)
      : rest;
}

ArticleImageBlock? _imageOf(String trimmed) {
  final match = _image.firstMatch(trimmed.trimRight());
  if (match == null) return null;
  var src = match.group(2)!;
  if (src.startsWith('<')) src = src.substring(1, src.length - 1);
  if (!isValidArticleResourceUrl(src)) return null;
  final caption = _unescape(match.group(3) ?? '');
  return ArticleImageBlock(
    id: '',
    src: src,
    alt: _unescape(match.group(1)!),
    caption: caption.isEmpty ? null : caption,
  );
}

ArticleTextBlock _textBlock(ArticleTextKind kind, String source, {int? level}) {
  final runs = parseInlineRuns(source);
  return ArticleTextBlock(
    id: '',
    kind: kind,
    text: runs.map((run) => run.text).join(),
    runs: runs,
    level: level,
  );
}

String _plainOf(String source) =>
    parseInlineRuns(source).map((run) => run.text).join();

const _punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';

String _unescape(String value) {
  final out = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final char = value[index];
    if (char == r'\' &&
        index + 1 < value.length &&
        _punctuation.contains(value[index + 1])) {
      out.write(value[index + 1]);
      index++;
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

/// Parses inline Markdown into runs whose text concatenates to the block's
/// plain text, merging neighbours that carry the same marks and link.
List<ArticleInlineRun> parseInlineRuns(String source) {
  final parser = _InlineParser(source);
  parser.parse(0, source.length, const {}, null);
  return parser.runs.isEmpty
      ? [ArticleInlineRun(text: source)]
      : List.unmodifiable(parser.runs);
}

class _Span {
  const _Span(this.start, this.end, this.after, [this.extra]);

  /// Content range, the index after the whole construct, and a payload
  /// (code text or link target).
  final int start;
  final int end;
  final int after;
  final String? extra;
}

class _InlineParser {
  _InlineParser(this.source);

  final String source;
  final List<ArticleInlineRun> runs = [];

  /// Closer searches already answered. Nested delimiters that never close
  /// would otherwise be searched again from every opener.
  final Map<String, int?> _closers = {};

  static const _starDelimiters = ['**', '__', '~~', '*', '_'];

  void parse(int start, int end, Set<ArticleInlineMark> marks, String? href) {
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      _emit(buffer.toString(), marks, href);
      buffer.clear();
    }

    var index = start;
    while (index < end) {
      final char = source[index];
      if (char == r'\' &&
          index + 1 < end &&
          _punctuation.contains(source[index + 1])) {
        buffer.write(source[index + 1]);
        index += 2;
        continue;
      }
      if (char == '`') {
        final span = _codeSpan(index, end);
        if (span != null) {
          flush();
          _emit(span.extra!, {...marks, ArticleInlineMark.code}, href);
          index = span.after;
        } else {
          final length = _runLength(index, end, '`');
          buffer.write(source.substring(index, index + length));
          index += length;
        }
        continue;
      }
      if (char == '[' && href == null) {
        final link = _link(index, end);
        if (link != null) {
          flush();
          parse(link.start, link.end, marks, link.extra);
          index = link.after;
          continue;
        }
      }
      if (source.startsWith('<u>', index) &&
          !marks.contains(ArticleInlineMark.underline)) {
        final close = _findCloser(index + 3, end, '</u>');
        if (close != null && close > index + 3) {
          flush();
          parse(index + 3, close, {
            ...marks,
            ArticleInlineMark.underline,
          }, href);
          index = close + 4;
          continue;
        }
      }
      final delimiter = _delimiterAt(index, end);
      if (delimiter != null) {
        final mark = _markOf(delimiter);
        if (!marks.contains(mark) && _canOpen(index, end, delimiter)) {
          final close = _findCloser(index + delimiter.length, end, delimiter);
          if (close != null) {
            flush();
            parse(index + delimiter.length, close, {...marks, mark}, href);
            index = close + delimiter.length;
            continue;
          }
        }
        buffer.write(delimiter);
        index += delimiter.length;
        continue;
      }
      buffer.write(char);
      index++;
    }
    flush();
  }

  void _emit(String text, Set<ArticleInlineMark> marks, String? href) {
    if (text.isEmpty) return;
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.href == href && _sameMarks(last.marks, marks)) {
      runs[runs.length - 1] = ArticleInlineRun(
        text: last.text + text,
        marks: last.marks,
        href: href,
      );
      return;
    }
    runs.add(
      ArticleInlineRun(text: text, marks: Set.unmodifiable(marks), href: href),
    );
  }

  String? _delimiterAt(int index, int end) {
    for (final delimiter in _starDelimiters) {
      if (index + delimiter.length <= end &&
          source.startsWith(delimiter, index)) {
        return delimiter;
      }
    }
    return null;
  }

  static ArticleInlineMark _markOf(String delimiter) => switch (delimiter) {
    '**' || '__' => ArticleInlineMark.bold,
    '~~' => ArticleInlineMark.strikethrough,
    _ => ArticleInlineMark.italic,
  };

  static bool _isSpace(String char) => char.trim().isEmpty;

  static bool _isAsciiWord(String char) =>
      RegExp(r'[A-Za-z0-9]').hasMatch(char);

  /// An opener is followed by text, not space; `_` additionally does not open
  /// inside an ASCII word, so `snake_case_name` stays literal.
  bool _canOpen(int index, int end, String delimiter) {
    final next = index + delimiter.length;
    if (next >= end || _isSpace(source[next])) return false;
    if (delimiter.startsWith('_') &&
        index > 0 &&
        _isAsciiWord(source[index - 1])) {
      return false;
    }
    return true;
  }

  bool _canClose(int index, int contentStart, String delimiter) {
    if (index <= contentStart || _isSpace(source[index - 1])) return false;
    final after = index + delimiter.length;
    if (delimiter.startsWith('_') &&
        after < source.length &&
        _isAsciiWord(source[after])) {
      return false;
    }
    return true;
  }

  /// Finds where [delimiter] closes, stepping over escapes, code spans, links,
  /// underline tags and complete spans of the other emphasis delimiters, so
  /// `***both***` and `*a **b** c*` nest as written.
  int? _findCloser(int from, int end, String delimiter) {
    final key = '$from:$end:$delimiter';
    if (_closers.containsKey(key)) return _closers[key];
    final found = _searchCloser(from, end, delimiter);
    _closers[key] = found;
    return found;
  }

  int? _searchCloser(int from, int end, String delimiter) {
    var index = from;
    while (index < end) {
      final char = source[index];
      if (char == r'\' &&
          index + 1 < end &&
          _punctuation.contains(source[index + 1])) {
        index += 2;
        continue;
      }
      if (char == '`') {
        final span = _codeSpan(index, end);
        index = span?.after ?? index + _runLength(index, end, '`');
        continue;
      }
      if (delimiter == '</u>') {
        if (source.startsWith('</u>', index)) return index;
        index++;
        continue;
      }
      if (char == '[') {
        final link = _link(index, end);
        if (link != null) {
          index = link.after;
          continue;
        }
      }
      if (source.startsWith('<u>', index)) {
        final close = _findCloser(index + 3, end, '</u>');
        if (close != null) {
          index = close + 4;
          continue;
        }
      }
      final found = _delimiterAt(index, end);
      if (found == null) {
        index++;
        continue;
      }
      if (found != delimiter) {
        // Another delimiter: skip its whole span when it has one. A doubled
        // delimiter met while looking for its single form may instead close.
        if (_canOpen(index, end, found)) {
          final nested = _findCloser(index + found.length, end, found);
          if (nested != null) {
            index = nested + found.length;
            continue;
          }
        }
        if (found.length == 2 &&
            found[0] == delimiter[0] &&
            delimiter.length == 1 &&
            _canClose(index, from, delimiter)) {
          return index;
        }
        index += found.length;
        continue;
      }
      if (_canClose(index, from, delimiter)) return index;
      index += delimiter.length;
    }
    return null;
  }

  int _runLength(int index, int end, String char) {
    var length = 0;
    while (index + length < end && source[index + length] == char) {
      length++;
    }
    return length;
  }

  _Span? _codeSpan(int index, int end) {
    final open = _runLength(index, end, '`');
    var search = index + open;
    while (search < end) {
      if (source[search] != '`') {
        search++;
        continue;
      }
      final length = _runLength(search, end, '`');
      if (length == open) {
        var content = source.substring(index + open, search);
        if (content.length >= 2 &&
            content.startsWith(' ') &&
            content.endsWith(' ') &&
            content.trim().isNotEmpty) {
          content = content.substring(1, content.length - 1);
        }
        if (content.isEmpty) return null;
        return _Span(index + open, search, search + length, content);
      }
      search += length;
    }
    return null;
  }

  _Span? _link(int index, int end) {
    var depth = 0;
    var close = -1;
    for (var at = index; at < end; at++) {
      final char = source[at];
      if (char == r'\') {
        at++;
        continue;
      }
      if (char == '`') {
        final span = _codeSpan(at, end);
        if (span != null) at = span.after - 1;
        continue;
      }
      if (char == '[') depth++;
      if (char == ']') {
        depth--;
        if (depth == 0) {
          close = at;
          break;
        }
      }
    }
    if (close <= index + 1 || close + 1 >= end || source[close + 1] != '(') {
      return null;
    }
    var at = close + 2;
    String href;
    if (at < end && source[at] == '<') {
      final stop = source.indexOf('>', at);
      if (stop < 0 || stop >= end) return null;
      href = source.substring(at + 1, stop);
      at = stop + 1;
    } else {
      final start = at;
      while (at < end && source[at] != ')' && !_isSpace(source[at])) {
        at++;
      }
      href = source.substring(start, at);
    }
    if (at >= end || source[at] != ')' || !isValidArticleResourceUrl(href)) {
      return null;
    }
    return _Span(index + 1, close, at + 1, href);
  }
}

bool _sameMarks(Set<ArticleInlineMark> a, Set<ArticleInlineMark> b) =>
    a.length == b.length && a.containsAll(b);

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Renders [blocks] in the editor's dialect. The inverse of
/// [parseArticleMarkdown] for every block [editableBodyOf] accepts.
String renderArticleMarkdown(List<ArticleBlock> blocks) {
  final parts = <String>[];
  for (final block in blocks) {
    switch (block) {
      case ArticleTextBlock():
        final inline = renderInlineRuns(block.runs);
        switch (block.kind) {
          case ArticleTextKind.paragraph:
            parts.add(_escapeLines(inline, first: true));
          case ArticleTextKind.heading:
            parts.add('${'#' * (block.level ?? 2)} $inline');
          case ArticleTextKind.quote:
            parts.add(
              inline
                  .split('\n')
                  .map((line) => line.isEmpty ? '>' : '> $line')
                  .join('\n'),
            );
        }
      case ArticleListBlock():
        final lines = <String>[];
        for (var index = 0; index < block.items.length; index++) {
          final marker = block.ordered ? '${index + 1}. ' : '- ';
          final item = _escapeLines(
            renderInlineRuns(block.items[index].runs),
            first: false,
          );
          final itemLines = item.split('\n');
          lines.add('$marker${itemLines.first}');
          for (final line in itemLines.skip(1)) {
            lines.add('${' ' * marker.length}$line');
          }
        }
        parts.add(lines.join('\n'));
      case ArticleImageBlock():
        final src = RegExp(r'[\s()<>]').hasMatch(block.src)
            ? '<${block.src}>'
            : block.src;
        final caption = block.caption ?? '';
        final title = caption.isEmpty
            ? ''
            : ' "${caption.replaceAllMapped(RegExp(r'[\\"]'), (m) => '\\${m[0]}')}"';
        final alt = block.alt.replaceAllMapped(
          RegExp(r'[\\\[\]]'),
          (m) => '\\${m[0]}',
        );
        parts.add('![$alt]($src$title)');
      case ArticleCodeBlock():
        var longest = 0;
        for (final match in RegExp('`+').allMatches(block.code)) {
          if (match[0]!.length > longest) longest = match[0]!.length;
        }
        final fence = '`' * (longest < 3 ? 3 : longest + 1);
        parts.add('$fence${block.language}\n${block.code}\n$fence');
    }
  }
  return parts.join('\n\n');
}

/// Escapes the start of every line that would otherwise begin a block. The
/// first line of a list item already follows its marker and needs nothing.
String _escapeLines(String text, {required bool first}) {
  final lines = text.split('\n');
  for (var index = first ? 0 : 1; index < lines.length; index++) {
    final line = lines[index];
    final rest = line.trimLeft();
    final lead = line.substring(0, line.length - rest.length);
    if (rest.startsWith('#') ||
        rest.startsWith('>') ||
        _bulletEscape.hasMatch(rest)) {
      lines[index] = '$lead\\$rest';
    } else if (_orderedEscape.hasMatch(rest)) {
      final mark = rest.indexOf(RegExp(r'[.)]'));
      lines[index] = '$lead${rest.substring(0, mark)}\\${rest.substring(mark)}';
    }
  }
  return lines.join('\n');
}

const _stackOrder = [
  ArticleInlineMark.bold,
  ArticleInlineMark.italic,
  ArticleInlineMark.strikethrough,
  ArticleInlineMark.underline,
];

String _open(ArticleInlineMark mark) => switch (mark) {
  ArticleInlineMark.bold => '**',
  ArticleInlineMark.italic => '*',
  ArticleInlineMark.strikethrough => '~~',
  ArticleInlineMark.underline => '<u>',
  ArticleInlineMark.code => '',
};

String _close(ArticleInlineMark mark) =>
    mark == ArticleInlineMark.underline ? '</u>' : _open(mark);

/// Renders inline runs; the counterpart of [parseInlineRuns].
String renderInlineRuns(List<ArticleInlineRun> runs) {
  final normalized = normalizeInlineRuns(runs);
  final out = StringBuffer();
  var index = 0;
  while (index < normalized.length) {
    final href = normalized[index].href;
    var stop = index;
    while (stop < normalized.length && normalized[stop].href == href) {
      stop++;
    }
    final marked = _renderMarked(normalized.sublist(index, stop));
    if (href == null) {
      out.write(marked);
    } else {
      final target = RegExp(r'[()<>]').hasMatch(href) ? '<$href>' : href;
      out.write('[$marked]($target)');
    }
    index = stop;
  }
  return out.toString();
}

String _renderMarked(List<ArticleInlineRun> runs) {
  final out = StringBuffer();
  final open = <ArticleInlineMark>[];
  for (final run in runs) {
    final wanted = run.marks.difference({ArticleInlineMark.code});
    final keep = open.indexWhere((mark) => !wanted.contains(mark));
    if (keep >= 0) {
      for (final mark in open.sublist(keep).reversed) {
        out.write(_close(mark));
      }
      open.removeRange(keep, open.length);
    }
    for (final mark in _stackOrder) {
      if (wanted.contains(mark) && !open.contains(mark)) {
        out.write(_open(mark));
        open.add(mark);
      }
    }
    out.write(
      run.marks.contains(ArticleInlineMark.code)
          ? _codeSpanOf(run.text)
          : _escapeInline(run.text),
    );
  }
  for (final mark in open.reversed) {
    out.write(_close(mark));
  }
  return out.toString();
}

String _codeSpanOf(String text) {
  var longest = 0;
  for (final match in RegExp('`+').allMatches(text)) {
    if (match[0]!.length > longest) longest = match[0]!.length;
  }
  final fence = '`' * (longest + 1);
  final pad =
      text.startsWith('`') ||
          text.endsWith('`') ||
          (text.startsWith(' ') && text.endsWith(' ') && text.trim().isNotEmpty)
      ? ' '
      : '';
  return '$fence$pad$text$pad$fence';
}

String _escapeInline(String text) =>
    text.replaceAllMapped(RegExp(r'[\\*_~`\[\]<]'), (m) => '\\${m[0]}');

/// Canonical runs: emphasis never starts or ends on white space (the
/// Markdown delimiters cannot express that, and it does not show), and
/// neighbours with equal marks and link are merged.
List<ArticleInlineRun> normalizeInlineRuns(List<ArticleInlineRun> runs) {
  const edgeless = {
    ArticleInlineMark.bold,
    ArticleInlineMark.italic,
    ArticleInlineMark.strikethrough,
  };
  final split = <ArticleInlineRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) continue;
    if (run.marks.contains(ArticleInlineMark.code) ||
        !run.marks.any(edgeless.contains)) {
      split.add(run);
      continue;
    }
    final core = run.text.trim();
    if (core.isEmpty) {
      split.add(
        ArticleInlineRun(
          text: run.text,
          marks: run.marks.difference(edgeless),
          href: run.href,
        ),
      );
      continue;
    }
    final start = run.text.indexOf(core);
    final lead = run.text.substring(0, start);
    final trail = run.text.substring(start + core.length);
    final bare = run.marks.difference(edgeless);
    if (lead.isNotEmpty) {
      split.add(ArticleInlineRun(text: lead, marks: bare, href: run.href));
    }
    split.add(ArticleInlineRun(text: core, marks: run.marks, href: run.href));
    if (trail.isNotEmpty) {
      split.add(ArticleInlineRun(text: trail, marks: bare, href: run.href));
    }
  }
  final merged = <ArticleInlineRun>[];
  for (final run in split) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null &&
        last.href == run.href &&
        _sameMarks(last.marks, run.marks)) {
      merged[merged.length - 1] = ArticleInlineRun(
        text: last.text + run.text,
        marks: last.marks,
        href: last.href,
      );
    } else {
      merged.add(run);
    }
  }
  return merged;
}

/// Whether two block lists say the same thing, ignoring ids and the run
/// differences [normalizeInlineRuns] erases.
bool sameArticleBlocks(List<ArticleBlock> a, List<ArticleBlock> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!_sameBlock(a[index], b[index])) return false;
  }
  return true;
}

bool _sameBlock(ArticleBlock a, ArticleBlock b) {
  switch ((a, b)) {
    case (final ArticleTextBlock x, final ArticleTextBlock y):
      return x.kind == y.kind &&
          x.text == y.text &&
          (x.kind != ArticleTextKind.heading || x.level == y.level) &&
          (x.attribution ?? '') == (y.attribution ?? '') &&
          _sameRuns(x.runs, y.runs);
    case (final ArticleListBlock x, final ArticleListBlock y):
      if (x.ordered != y.ordered || x.items.length != y.items.length) {
        return false;
      }
      for (var index = 0; index < x.items.length; index++) {
        if (x.items[index].text != y.items[index].text ||
            !_sameRuns(x.items[index].runs, y.items[index].runs)) {
          return false;
        }
      }
      return true;
    case (final ArticleImageBlock x, final ArticleImageBlock y):
      return x.src == y.src &&
          x.alt == y.alt &&
          (x.caption ?? '') == (y.caption ?? '');
    case (final ArticleCodeBlock x, final ArticleCodeBlock y):
      return x.language == y.language && x.code == y.code;
    default:
      return false;
  }
}

bool _sameRuns(List<ArticleInlineRun> a, List<ArticleInlineRun> b) {
  final x = normalizeInlineRuns(a);
  final y = normalizeInlineRuns(b);
  if (x.length != y.length) return false;
  for (var index = 0; index < x.length; index++) {
    if (x[index].text != y[index].text ||
        x[index].href != y[index].href ||
        !_sameMarks(x[index].marks, y[index].marks)) {
      return false;
    }
  }
  return true;
}

/// Whether [blocks] are nothing but plain paragraphs - the shape the older
/// version 0 document stores as is.
bool isPlainParagraphs(List<ArticleBlock> blocks) => blocks.every(
  (block) =>
      block is ArticleTextBlock &&
      block.kind == ArticleTextKind.paragraph &&
      normalizeInlineRuns(
        block.runs,
      ).every((run) => run.marks.isEmpty && run.href == null),
);
