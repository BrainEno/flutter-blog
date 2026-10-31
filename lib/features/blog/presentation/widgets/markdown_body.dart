import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/app_logger.dart';
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
class MarkdownBody extends StatelessWidget {
  final String markdown;

  /// Optional reader-specific typography; the editor preview keeps the
  /// default theme text styles when these are not supplied.
  final TextStyle? bodyStyle;
  final TextStyle? headingStyle;

  const MarkdownBody({
    super.key,
    required this.markdown,
    this.bodyStyle,
    this.headingStyle,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = _parse(markdown);
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
      return _paragraph(context, [node]);
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
        return _paragraph(context, node.children ?? const []);
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
            child: Text(
              // Fenced blocks carry a trailing newline in the AST; trim it
              // so the rendered block does not end with a blank line.
              node.textContent.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
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
        return _paragraph(context, [node]);
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
    return Text.rich(
      TextSpan(
        style: (headingStyle ?? Theme.of(context).textTheme.bodyLarge)
            ?.copyWith(
              fontSize: size,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
        children: _inline(context, element.children ?? const []),
      ),
    );
  }

  Widget _paragraph(BuildContext context, List<md.Node> nodes) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style:
              bodyStyle ??
              Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          children: _inline(context, nodes),
        ),
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
                        for (final child
                            in items[i].children ?? const <md.Node>[])
                          if (child is md.Element &&
                              (child.tag == 'ul' || child.tag == 'ol'))
                            _list(context, child, nextIndent)
                          else
                            _block(context, child, nextIndent),
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

  List<InlineSpan> _inline(BuildContext context, List<md.Node> nodes) {
    return [for (final node in nodes) _inlineNode(context, node)];
  }

  InlineSpan _inlineNode(BuildContext context, md.Node node) {
    if (node is md.Text) {
      return TextSpan(text: node.text);
    }
    if (node is! md.Element) {
      return TextSpan(text: node.textContent);
    }
    switch (node.tag) {
      case 'strong':
        return TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: _inline(context, node.children ?? const []),
        );
      case 'em':
        return TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: _inline(context, node.children ?? const []),
        );
      case 'code':
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              node.textContent,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        );
      case 'a':
        final href = node.attributes['href'] ?? '';
        return TextSpan(
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: _httpUrl(href) == null
              ? null
              : (TapGestureRecognizer()..onTap = () => _launch(context, href)),
          children: _inline(context, node.children ?? const []),
        );
      case 'img':
        final src = node.attributes['src'] ?? '';
        final uri = _httpUrl(src);
        final l10n = context.l10n;
        if (uri == null) {
          return TextSpan(text: l10n.markdownImageAlt);
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
        return TextSpan(children: _inline(context, node.children ?? const []));
    }
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
