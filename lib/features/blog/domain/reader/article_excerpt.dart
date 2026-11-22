import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';

/// The few lines a list row shows under an article's title.
///
/// An excerpt the author wrote - a Notion page's `Excerpt` property, or a
/// summary typed on the web - is shown as written. Otherwise the row shows
/// the opening of the body, cut at [limit] characters.
///
/// The server fills an empty summary with its own cut of the opening, so a
/// non-empty [Blog.summary] alone does not mean the author wrote one. A
/// summary that is only the beginning of the body is the server's, and the
/// row makes its own (longer) cut instead - the same test the web uses
/// before it prints a standfirst (`repeatsArticleOpening`).
///
/// A cut never ends on punctuation: trailing marks are dropped and `...`
/// follows the last character. Text that fits is returned whole, ending the
/// way the author ended it, because nothing was left out.
String articleExcerpt(
  Blog blog, {
  int limit = AppLimits.articleExcerptCharacters,
}) {
  final pieces = _openingPieces(blog);
  final summary = _collapse(blog.summary);
  if (summary.isNotEmpty && !_repeatsOpening(summary, pieces)) {
    return excerptOf(summary, limit: limit);
  }
  return excerptOf(_join(pieces, readable: true), limit: limit);
}

/// [text] cut to at most [limit] code points, closed with `...` when
/// anything was cut. Exposed for the tests and for rows built from plain
/// text.
String excerptOf(
  String text, {
  int limit = AppLimits.articleExcerptCharacters,
}) {
  final source = _collapse(text);
  final runes = source.runes.toList();
  if (runes.length <= limit) return source;
  var cut = String.fromCharCodes(runes.take(limit));
  // A Latin word split in the middle reads as a typo; step back to the last
  // space when the cut fell inside one. Chinese has no spaces to find and
  // every character is already a whole word.
  if (_isLatin(runes[limit - 1]) && _isLatin(runes[limit])) {
    final space = cut.lastIndexOf(' ');
    if (space > 0) cut = cut.substring(0, space);
  }
  final closed = cut.replaceFirst(_trailingMarks, '');
  if (closed.isEmpty) return '';
  return '$closed$_ellipsis';
}

const _ellipsis = '...';

/// Punctuation, symbols, spaces and the invisible joiners an emoji leaves
/// behind when it is cut: none of them may stand before the ellipsis.
final _trailingMarks = RegExp(
  r'[\p{P}\p{S}\p{Z}\p{Cf}\s\uFE0E\uFE0F]+$',
  unicode: true,
);

final _whitespace = RegExp(r'\s+');
final _latinEdge = RegExp(r'[A-Za-z0-9]');
final _latinLetter = RegExp(r'[A-Za-z0-9\u00C0-\u024F]');
final _wideMark = RegExp(r'[^\x00-\x7F]', unicode: true);
final _punctuation = RegExp(r'\p{P}$', unicode: true);

bool _isLatin(int rune) => _latinLetter.hasMatch(String.fromCharCode(rune));

String _collapse(String value) => value.replaceAll(_whitespace, ' ').trim();

/// The prose of the body in reading order, one entry per block. Images and
/// code carry no prose, as in the server's own summary.
List<String> _openingPieces(Blog blog) {
  final document = blog.document;
  final pieces = <String>[];
  if (document != null && document.supported && document.blocks.isNotEmpty) {
    for (final block in document.blocks) {
      switch (block) {
        case ArticleTextBlock(:final text):
          pieces.add(text);
        case ArticleListBlock(:final items):
          pieces.add(
            items
                .map((item) => item.text.trim())
                .where((text) => text.isNotEmpty)
                .join('\uFF0C'),
          );
        case ArticleImageBlock() || ArticleCodeBlock():
          break;
      }
    }
  } else {
    pieces.addAll(_markdownParagraphs(blog.content));
  }
  return [
    for (final piece in pieces)
      if (_collapse(piece).isNotEmpty) _collapse(piece),
  ];
}

/// Paragraphs of a legacy Markdown body with the markup taken out, so a row
/// never prints a `#` or a link target.
List<String> _markdownParagraphs(String content) {
  final paragraphs = <String>[];
  final current = <String>[];
  var inFence = false;
  void flush() {
    if (current.isNotEmpty) paragraphs.add(current.join(' '));
    current.clear();
  }

  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      flush();
      continue;
    }
    if (inFence) continue;
    if (line.isEmpty) {
      flush();
      continue;
    }
    final text = line
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
        .replaceAllMapped(
          RegExp(r'\[([^\]]*)\]\([^)]*\)'),
          (match) => match[1] ?? '',
        )
        .replaceFirst(RegExp(r'^(#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+)'), '')
        .replaceAll(RegExp(r'(\*\*|__|`)'), '')
        .trim();
    if (text.isNotEmpty) current.add(text);
  }
  flush();
  return paragraphs;
}

/// Joins block texts. The server's join (`readable: false`) puts a space only
/// between two Latin words, which is what a generated summary is compared
/// against. The row's own join also keeps a heading apart from the paragraph
/// after it: a space wherever the earlier block did not end on wide
/// (Chinese) punctuation.
String _join(List<String> pieces, {required bool readable}) {
  final buffer = StringBuffer();
  for (final piece in pieces) {
    if (buffer.isNotEmpty) {
      final before = buffer.toString();
      final last = before[before.length - 1];
      final latinPair =
          _latinEdge.hasMatch(last) && _latinEdge.hasMatch(piece[0]);
      final widePause = _punctuation.hasMatch(last) && _wideMark.hasMatch(last);
      if (latinPair || (readable && !widePause)) buffer.write(' ');
    }
    buffer.write(piece);
  }
  return buffer.toString();
}

/// Whether [summary] is only the start of the body: the server's generated
/// summary, possibly closed with an ellipsis, not an excerpt anyone wrote.
bool _repeatsOpening(String summary, List<String> pieces) {
  final excerpt = summary
      .replaceFirst(RegExp(r'(\u2026|\.\.\.)$'), '')
      .trimRight();
  if (excerpt.isEmpty) return false;
  return _join(pieces, readable: false).startsWith(excerpt);
}
