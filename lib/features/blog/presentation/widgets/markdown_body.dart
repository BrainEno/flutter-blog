import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/presentation/markdown/markdown_renderer.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders a Markdown document as Flutter widgets (issue #17).
///
/// Owns the parse result and the link recognizers (they must be disposed with
/// the widget); the rendering itself is [MarkdownRenderer]. Safety model:
/// parsing uses the Dart-team `markdown` package, which produces an AST -
/// never HTML. Only http(s) links can be tapped open (through url_launcher)
/// and only http(s) images render, so arbitrary schemes, scripts or inline
/// HTML cannot execute. Unknown constructs degrade to their plain text.
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
    return MarkdownRenderer(
      nodes: nodes,
      links: _links,
      bodyStyle: bodyStyle,
      headingStyle: headingStyle,
      readAloudDocument: readAloudDocument,
      readAloudController: readAloudController,
      readAloudBlockKeys: readAloudBlockKeys,
    ).build(context);
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
}
