/// A typed, read-only representation of no-wave's versioned article body.
/// It contains no storage or widget types. Unknown documents are represented
/// explicitly so the reader can warn instead of implying a complete render.
class ArticleDocument {
  const ArticleDocument({required this.version, required this.blocks})
    : supported = true;

  const ArticleDocument.unsupported(this.version)
    : supported = false,
      blocks = const [];

  final int? version;
  final bool supported;
  final List<ArticleBlock> blocks;

  bool get hasImages => blocks.any((block) => block is ArticleImageBlock);
}

enum ArticleInlineMark { bold, italic, underline, strikethrough, code }

enum ArticleTextKind { paragraph, heading, quote }

class ArticleInlineRun {
  const ArticleInlineRun({
    required this.text,
    this.marks = const {},
    this.href,
  });

  final String text;
  final Set<ArticleInlineMark> marks;
  final String? href;
}

sealed class ArticleBlock {
  const ArticleBlock({required this.id});
  final String id;
}

final class ArticleTextBlock extends ArticleBlock {
  const ArticleTextBlock({
    required super.id,
    required this.kind,
    required this.text,
    required this.runs,
    this.level,
    this.attribution,
  });

  final ArticleTextKind kind;
  final String text;
  final List<ArticleInlineRun> runs;
  final int? level;
  final String? attribution;
}

class ArticleListItem {
  const ArticleListItem({required this.text, required this.runs});
  final String text;
  final List<ArticleInlineRun> runs;
}

final class ArticleListBlock extends ArticleBlock {
  const ArticleListBlock({
    required super.id,
    required this.ordered,
    required this.items,
  });
  final bool ordered;
  final List<ArticleListItem> items;
}

final class ArticleImageBlock extends ArticleBlock {
  const ArticleImageBlock({
    required super.id,
    required this.src,
    required this.alt,
    this.caption,
  });
  final String src;
  final String alt;
  final String? caption;
}

final class ArticleCodeBlock extends ArticleBlock {
  const ArticleCodeBlock({
    required super.id,
    required this.language,
    required this.code,
  });
  final String language;
  final String code;
}
