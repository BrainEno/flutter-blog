import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_highlight.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Renders a Markdown document as Flutter widgets (issue #17).
///
/// Safety model: parsing uses the Dart-team `markdown` package, which
/// produces an AST - never HTML. Only http(s) links can be tapped open
/// (through url_launcher) and only http(s) images render, so arbitrary
/// schemes, scripts or inline HTML cannot execute. Unknown constructs
/// degrade to their plain text.
class MarkdownBody extends StatefulWidget {
  final String markdown;

  /// Optional reader-specific typography; the editor preview keeps the
  /// default theme text styles when these are not supplied.
  final TextStyle? bodyStyle;
  final TextStyle? headingStyle;

  /// Optional shared reader parse and block notifiers. Editor previews keep
  /// their existing behavior and do not create a speech engine.
  final ReadAloudDocument? readAloudDocument;
  final ReadAloudController? readAloudController;
  final List<GlobalKey>? readAloudBlockKeys;

  const MarkdownBody({
    super.key,
    required this.markdown,
    this.bodyStyle,
    this.headingStyle,
    this.readAloudDocument,
    this.readAloudController,
    this.readAloudBlockKeys,
  });

  @override
  State<MarkdownBody> createState() => _MarkdownBodyState();
}

class _MarkdownBodyState extends State<MarkdownBody> {
  final Map<md.Node, TapGestureRecognizer> _links = {};
  late List<md.Node> _nodes;

  TextStyle? get bodyStyle => widget.bodyStyle;
  TextStyle? get headingStyle => widget.headingStyle;
  ReadAloudDocument? get readAloudDocument => widget.readAloudDocument;
  ReadAloudController? get readAloudController => widget.readAloudController;
  List<GlobalKey>? get readAloudBlockKeys => widget.readAloudBlockKeys;

  @override
  void initState() {
    super.initState();
    _resetNodes();
  }

  @override
  void didUpdateWidget(covariant MarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown ||
        oldWidget.readAloudDocument != widget.readAloudDocument) {
      _resetNodes();
    }
  }

  void _resetNodes() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    _links.clear();
    _nodes = readAloudDocument?.nodes ?? _parse(widget.markdown);
  }

  @override
  void dispose() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _nodes;
    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) _block(context, node, EdgeInsets.zero),
      ],
    );
  }

  /// The parser is total (bad Markdown degrades to text nodes), but a
  /// crash here must never take the reader down.
  static List<md.Node> _parse(String source) {
    try {
      return md.Document().parseLines(source.split('\n'));
    } catch (e, stackTrace) {
      AppLogger.error(
        'parsing markdown failed',
        error: e,
        stackTrace: stackTrace,
      );
      return md.Document().parseLines(const []);
    }
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
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: _heading(context, node),
        );
      case 'p':
        return _paragraph(context, node.children ?? const [], owner: node);
      case 'blockquote':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 14),
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
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _followBlock(
              node,
              (highlight, block) => Text.rich(
                readAloudTextSpan(
                  // Match the visible trimmed fenced-code text exactly.
                  text: node.textContent.trim(),
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
          ),
        );
      case 'hr':
        return const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 12),
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
    return _followBlock(
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
    );
  }

  Widget _paragraph(
    BuildContext context,
    List<md.Node> nodes, {
    required md.Node owner,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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
    final nextIndent = indent + const EdgeInsets.only(left: 16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
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
  }) {
    return [
      for (final node in nodes)
        _inlineNode(context, node, block, highlight, link),
    ];
  }

  InlineSpan _inlineNode(
    BuildContext context,
    md.Node node,
    SpeechBlock? block,
    ReadAloudHighlight? highlight,
    TapGestureRecognizer? link,
  ) {
    if (node is md.Text) {
      return readAloudTextSpan(
        text: node.text,
        range: block?.inlineRanges[node],
        highlight: highlight,
        recognizer: link,
      );
    }
    if (node is! md.Element) {
      return readAloudTextSpan(
        text: node.textContent,
        range: block?.inlineRanges[node],
        highlight: highlight,
        recognizer: link,
      );
    }
    switch (node.tag) {
      case 'strong':
        return TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: _inline(
            context,
            node.children ?? const [],
            block,
            highlight,
            link: link,
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
          ),
        );
      case 'code':
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _linkWidget(
            link,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text.rich(
                readAloudTextSpan(
                  text: node.textContent,
                  range: block?.inlineRanges[node],
                  highlight: highlight,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ),
          ),
        );
      case 'a':
        final href = node.attributes['href'] ?? '';
        final recognizer = _httpUrl(href) == null
            ? null
            : _links.putIfAbsent(
                node,
                () =>
                    TapGestureRecognizer()
                      ..onTap = () => _launch(context, href),
              );
        return TextSpan(
          style: TextStyle(
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
          ),
        );
      case 'img':
        final src = node.attributes['src'] ?? '';
        final uri = _httpUrl(src);
        final l10n = context.l10n;
        if (uri == null) {
          // Keep image placeholders to one rendered paragraph position, like
          // valid image WidgetSpans, without ever loading an unsafe URL.
          return WidgetSpan(child: Text(l10n.markdownImageAlt));
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
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
                      height: 40,
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
          ),
        );
    }
  }

  Widget _linkWidget(TapGestureRecognizer? link, Widget child) {
    if (link == null) return child;
    return GestureDetector(onTap: link.onTap, child: child);
  }

  /// Only http(s) targets can be opened or loaded. Everything else
  /// (javascript:, file:, custom schemes, ...) is inert text.
  static Uri? _httpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    return (uri.scheme == 'http' || uri.scheme == 'https') ? uri : null;
  }

  static void _launch(BuildContext context, String href) {
    final uri = _httpUrl(href);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((e) {
      AppLogger.error('opening a markdown link failed', error: e);
      return false;
    });
  }
}
