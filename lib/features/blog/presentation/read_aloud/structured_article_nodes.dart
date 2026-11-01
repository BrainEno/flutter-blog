import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:markdown/markdown.dart' as md;

/// Converts trusted, validated article blocks to the same inert AST consumed
/// by MarkdownBody and ReadAloudDocument. Text is never parsed as Markdown or
/// HTML; inline formatting comes only from the server's explicit marks.
List<md.Node> structuredArticleNodes(
  ArticleDocument document, {
  String? webBaseUrl,
}) {
  if (!document.supported) return const [];

  List<md.Node> inlines(List<ArticleInlineRun> runs) => [
    for (final run in runs) _inline(run, webBaseUrl),
  ];

  final nodes = <md.Node>[];
  for (final block in document.blocks) {
    switch (block) {
      case ArticleTextBlock():
        final children = inlines(block.runs);
        switch (block.kind) {
          case ArticleTextKind.paragraph:
            nodes.add(md.Element('p', children));
          case ArticleTextKind.heading:
            nodes.add(md.Element('h${block.level}', children));
          case ArticleTextKind.quote:
            nodes.add(
              md.Element('blockquote', [
                md.Element('p', children),
                if (block.attribution != null && block.attribution!.isNotEmpty)
                  md.Element('p', [md.Text('— ${block.attribution}')]),
              ]),
            );
        }
      case ArticleListBlock():
        nodes.add(
          md.Element(block.ordered ? 'ol' : 'ul', [
            for (final item in block.items)
              md.Element('li', inlines(item.runs)),
          ]),
        );
      case ArticleImageBlock():
        final image = md.Element.empty('img')
          ..attributes['src'] =
              resolveArticleResourceUrl(
                block.src,
                webBaseUrl: webBaseUrl,
              )?.toString() ??
              ''
          ..attributes['alt'] = block.alt;
        nodes.add(md.Element('p', [image]));
        if (block.caption != null && block.caption!.isNotEmpty) {
          nodes.add(md.Element('p', [md.Text(block.caption!)]));
        }
      case ArticleCodeBlock():
        final pre =
            md.Element('pre', [
                md.Element('code', [md.Text(block.code)]),
              ])
              ..attributes['data-preserve-whitespace'] = 'true'
              ..attributes['data-language'] = block.language;
        nodes.add(pre);
    }
  }
  return nodes;
}

md.Node _inline(ArticleInlineRun run, String? webBaseUrl) {
  final isCode = run.marks.contains(ArticleInlineMark.code);
  md.Node node = md.Element(isCode ? 'code' : 'span', [md.Text(run.text)])
    ..attributes['data-bold'] = run.marks.contains(ArticleInlineMark.bold)
        ? 'true'
        : 'false'
    ..attributes['data-italic'] = run.marks.contains(ArticleInlineMark.italic)
        ? 'true'
        : 'false'
    ..attributes['data-underline'] =
        run.marks.contains(ArticleInlineMark.underline) ? 'true' : 'false'
    ..attributes['data-strikethrough'] =
        run.marks.contains(ArticleInlineMark.strikethrough) ? 'true' : 'false';
  final href = run.href;
  if (href != null) {
    final resolved = resolveArticleResourceUrl(href, webBaseUrl: webBaseUrl);
    if (resolved != null) {
      node = md.Element('a', [node])..attributes['href'] = resolved.toString();
    }
  }
  return node;
}
