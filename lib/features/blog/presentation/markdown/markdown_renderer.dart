import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/features/blog/presentation/markdown/markdown_styles.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_highlight.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Turns a parsed Markdown AST into widgets.
///
/// One object per build: the AST, the tap recognizers and the read-aloud
/// hooks are passed in, so this class holds no state of its own and
/// [MarkdownBody] keeps owning the recognizer lifecycle. Safety model: only
/// http(s) links are tappable and only http(s) images load, so arbitrary
/// schemes and inline HTML stay inert text.
class MarkdownRenderer {
  MarkdownRenderer({
    required this.nodes,
    required this.links,
    required this.bodyStyle,
    required this.headingStyle,
    required this.readAloudDocument,
    required this.readAloudController,
    required this.readAloudBlockKeys,
  });

  /// The parsed document, in render order.
  final List<md.Node> nodes;

  /// Tap recognizers keyed by node; owned and disposed by the widget state.
  final Map<md.Node, TapGestureRecognizer> links;

  /// Optional reader typography; the editor preview keeps the theme styles.
  final TextStyle? bodyStyle;
  final TextStyle? headingStyle;

  /// Optional reader hooks; the editor preview passes none of them.
  final ReadAloudDocument? readAloudDocument;
  final ReadAloudController? readAloudController;
  final List<GlobalKey>? readAloudBlockKeys;

  /// Renders every block of [nodes] as one column.
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) _block(context, node, EdgeInsets.zero),
      ],
    );
  }

  Widget _block(BuildContext context, md.Node node, EdgeInsets indent) {
    if (node is! md.Element) {
      return _paragraph(context, [node], owner: node);
    }
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return Padding(
          padding: const EdgeInsets.only(
            top: NoWaveSpacing.large,
            bottom: NoWaveSpacing.small,
          ),
          child: _heading(context, node),
        );
      case 'p':
        return _paragraph(context, node.children ?? const [], owner: node);
      case 'blockquote':
        return Padding(
          padding: const EdgeInsets.only(
            top: NoWaveSpacing.small,
            bottom: NoWaveSpacing.small,
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: NoWaveSpacing.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final child in node.children ?? const <md.Node>[])
                  _block(context, child, EdgeInsets.zero),
              ],
            ),
          ),
        );
      case 'ul':
      case 'ol':
        return _list(context, node, indent);
      case 'pre':
        final language = node.attributes['data-language'];
        return Padding(
          padding: const EdgeInsets.only(
            top: NoWaveSpacing.small,
            bottom: NoWaveSpacing.small,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(NoWaveSpacing.small),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (language != null && language.isNotEmpty) ...[
                  Text(language, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: NoWaveSpacing.xs),
                ],
                _followBlock(
                  node,
                  (highlight, block) => Text.rich(
                    readAloudTextSpan(
                      text: markdownCodeText(node),
                      range: block?.inlineRanges[node],
                      highlight: highlight,
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'hr':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: NoWaveSpacing.medium),
          child: Divider(),
        );
      default:
        // Unknown block-level construct: show its text, never crash.
        return _paragraph(context, [node], owner: node);
    }
  }

  Widget _heading(BuildContext context, md.Element element) {
    final level = int.tryParse(element.tag.substring(1)) ?? 3;
    final size = switch (level) {
      1 => 26.0,
      2 => 22.0,
      3 => 19.0,
      _ => 17.0,
    };
    return Semantics(
      header: true,
      child: _followBlock(
        element,
        (highlight, block) => Text.rich(
          TextSpan(
            style: (headingStyle ?? Theme.of(context).textTheme.bodyLarge)
                ?.copyWith(
                  fontSize: size,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
            children: _inline(
              context,
              element.children ?? const [],
              block,
              highlight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _paragraph(
    BuildContext context,
    List<md.Node> nodes, {
    required md.Node owner,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.xs),
      child: _followBlock(
        owner,
        (highlight, block) => Text.rich(
          TextSpan(
            style:
                bodyStyle ??
                Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
            children: _inline(context, nodes, block, highlight),
          ),
        ),
      ),
    );
  }

  Widget _followBlock(
    md.Node node,
    Widget Function(ReadAloudHighlight?, SpeechBlock?) builder,
  ) {
    final block = readAloudDocument?.blockByNode[node];
    final controller = readAloudController;
    if (block == null || controller == null) return builder(null, null);
    final keys = readAloudBlockKeys;
    return KeyedSubtree(
      key: keys != null && block.index < keys.length ? keys[block.index] : null,
      child: ValueListenableBuilder<ReadAloudHighlight?>(
        valueListenable: controller.highlights[block.index],
        builder: (context, highlight, child) => builder(highlight, block),
      ),
    );
  }

  Widget _list(BuildContext context, md.Element list, EdgeInsets indent) {
    final ordered = list.tag == 'ol';
    final items = (list.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((element) => element.tag == 'li')
        .toList();
    final nextIndent =
        indent + const EdgeInsets.only(left: NoWaveSpacing.medium);
    return Padding(
      padding: const EdgeInsets.only(bottom: NoWaveSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(
                // Rows of one list are tighter than any step.
                bottom: 2, // design-token-ok: rows of one list
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26, // design-token-ok: marker column
                    child: Text(
                      ordered ? '${i + 1}.' : '•',
                      style:
                          (bodyStyle ?? Theme.of(context).textTheme.bodyLarge)
                              ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final part in markdownListParts(items[i]))
                          _listPart(context, part, nextIndent),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _listPart(
    BuildContext context,
    MarkdownListPart part,
    EdgeInsets indent,
  ) {
    final inline = part.inline;
    if (inline != null) return _paragraph(context, inline, owner: part.owner);
    final node = part.owner;
    if (node is md.Element && (node.tag == 'ul' || node.tag == 'ol')) {
      return _list(context, node, indent);
    }
    return _block(context, node, indent);
  }

  List<InlineSpan> _inline(
    BuildContext context,
    List<md.Node> nodes,
    SpeechBlock? block,
    ReadAloudHighlight? highlight, {
    TapGestureRecognizer? link,
    TextDecoration? decoration,
  }) {
    return [
      for (final node in nodes)
        _inlineNode(context, node, block, highlight, link, decoration),
    ];
  }

  InlineSpan _inlineNode(
    BuildContext context,
    md.Node node,
    SpeechBlock? block,
    ReadAloudHighlight? highlight,
    TapGestureRecognizer? link,
    TextDecoration? decoration,
  ) {
    if (node is md.Text) {
      return readAloudTextSpan(
        text: node.text,
        range: block?.inlineRanges[node],
        highlight: highlight,
        recognizer: link,
        existingDecoration: decoration,
      );
    }
    if (node is! md.Element) {
      return readAloudTextSpan(
        text: node.textContent,
        range: block?.inlineRanges[node],
        highlight: highlight,
        recognizer: link,
        existingDecoration: decoration,
      );
    }
    switch (node.tag) {
      case 'span':
        final style = structuredMarksStyle(node, link: link != null);
        final combined = combineDecorations(decoration, style.decoration);
        return TextSpan(
          style: style.copyWith(decoration: combined),
          children: _inline(
            context,
            node.children ?? const [],
            block,
            highlight,
            link: link,
            decoration: combined,
          ),
        );
      case 'strong':
        return TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: _inline(
            context,
            node.children ?? const [],
            block,
            highlight,
            link: link,
            decoration: decoration,
          ),
        );
      case 'em':
        return TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: _inline(
            context,
            node.children ?? const [],
            block,
            highlight,
            link: link,
            decoration: decoration,
          ),
        );
      case 'code':
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _linkWidget(
            link,
            Container(
              padding: const EdgeInsets.symmetric(
                // A chip hugs the glyphs it wraps.
                horizontal: 5, // design-token-ok: chip hugs its glyphs
                vertical: 1, // design-token-ok: chip hugs its glyphs
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text.rich(
                readAloudTextSpan(
                  text: node.textContent,
                  range: block?.inlineRanges[node],
                  highlight: highlight,
                  existingDecoration: combineDecorations(
                    decoration,
                    structuredMarksStyle(node, link: link != null).decoration,
                  ),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14)
                    .merge(structuredMarksStyle(node, link: link != null))
                    .copyWith(
                      color: link == null
                          ? null
                          : Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ),
        );
      case 'a':
        final href = node.attributes['href'] ?? '';
        final recognizer = _httpUrl(href) == null
            ? null
            : links.putIfAbsent(
                node,
                () =>
                    TapGestureRecognizer()
                      ..onTap = () => _launch(context, href),
              );
        return TextSpan(
          style: recognizer == null
              ? null
              : TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
          recognizer: recognizer,
          children: _inline(
            context,
            node.children ?? const [],
            block,
            highlight,
            link: recognizer,
            decoration: recognizer == null
                ? decoration
                : combineDecorations(decoration, TextDecoration.underline),
          ),
        );
      case 'img':
        final src = node.attributes['src'] ?? '';
        final uri = _httpUrl(src);
        final l10n = context.l10n;
        if (uri == null) {
          // Keep image placeholders to one rendered paragraph position, like
          // valid image WidgetSpans, without ever loading an unsafe URL.
          final alt = (node.attributes['alt'] ?? '').trim();
          return WidgetSpan(
            child: Semantics(
              image: true,
              excludeSemantics: true,
              label: alt.isEmpty
                  ? l10n.articleImageUnavailable
                  : '$alt, ${l10n.articleImageUnavailable}',
              child: Text(l10n.articleImageUnavailable),
            ),
          );
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.xs),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Semantics(
                  image: true,
                  label: (node.attributes['alt'] ?? '').trim().isEmpty
                      ? l10n.imageLabel
                      : node.attributes['alt'],
                  child: CachedNetworkImage(
                    imageUrl: uri.toString(),
                    fit: BoxFit.contain,
                    errorWidget: (context, error, stackTrace) => SizedBox(
                      // A failed image keeps its slot instead of collapsing.
                      height: 40, // design-token-ok: failed image slot
                      child: Center(child: Text(l10n.markdownImageFailed)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case 'br':
        return const TextSpan(text: '\n');
      default:
        return TextSpan(
          children: _inline(
            context,
            node.children ?? const [],
            block,
            highlight,
            link: link,
            decoration: decoration,
          ),
        );
    }
  }

  Widget _linkWidget(TapGestureRecognizer? link, Widget child) {
    if (link == null) return child;
    // A link that wraps an inline code span becomes a WidgetSpan, so the
    // paragraph's own inline semantics cannot describe it (issue #24).
    // Without this annotation a reader sees plain text and a bare
    // GestureDetector: no "link" role, no tap action, nothing to activate
    // with TalkBack/VoiceOver. The gesture stays on the child so the
    // pointer and the assistive-tech action share one code path.
    return Semantics(
      link: true,
      child: GestureDetector(onTap: link.onTap, child: child),
    );
  }

  /// Only http(s) targets can be opened or loaded. Everything else
  /// (javascript:, file:, custom schemes, ...) is inert text.
  static Uri? _httpUrl(String value) => resolveArticleResourceUrl(value);

  static void _launch(BuildContext context, String href) {
    final uri = _httpUrl(href);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((e) {
      AppLogger.error('opening a markdown link failed', error: e);
      return false;
    });
  }
}
