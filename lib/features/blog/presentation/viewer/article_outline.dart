import 'package:belog/core/config/app_limits.dart';
import 'package:markdown/markdown.dart' as md;

/// One heading of an article, as the contents list shows it.
class OutlineEntry {
  const OutlineEntry({
    required this.node,
    required this.depth,
    required this.title,
  });

  /// The heading in the rendered document, so the page can find it.
  final md.Element node;

  /// How far in the entry sits: 0 for the article's top heading level, at
  /// most [ArticleOutline.maxDepth].
  final int depth;

  /// The heading's words on one line.
  final String title;
}

/// The headings of an article, in reading order.
///
/// Only headings of the body itself count - not one quoted inside a block
/// quote or a list item - and a heading with no words is skipped. Depth is
/// measured from the shallowest level the article uses, so a piece written
/// with only `##` and `###` starts flush rather than one step in.
class ArticleOutline {
  ArticleOutline._(this.entries);

  /// Deeper headings share the last step: the list stays a list, not a
  /// staircase.
  static const int maxDepth = 2;

  static final RegExp _heading = RegExp(r'^h([1-6])$');
  static final RegExp _space = RegExp(r'\s+');

  factory ArticleOutline.of(List<md.Node> nodes) {
    final found = <(md.Element, int, String)>[];
    for (final node in nodes) {
      if (node is! md.Element) continue;
      final match = _heading.firstMatch(node.tag);
      if (match == null) continue;
      final title = node.textContent.replaceAll(_space, ' ').trim();
      if (title.isEmpty) continue;
      found.add((node, int.parse(match.group(1)!), title));
    }
    if (found.isEmpty) return ArticleOutline._(const []);
    final top = found.map((heading) => heading.$2).reduce(_min);
    return ArticleOutline._(
      List.unmodifiable([
        for (final (node, level, title) in found)
          OutlineEntry(
            node: node,
            depth: (level - top).clamp(0, maxDepth),
            title: title,
          ),
      ]),
    );
  }

  static int _min(int a, int b) => a < b ? a : b;

  final List<OutlineEntry> entries;

  /// Whether there are enough headings for a contents list to help.
  bool get worthShowing => entries.length >= AppLimits.outlineMinHeadings;
}
