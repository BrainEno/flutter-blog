import 'dart:async';

import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/read_aloud/structured_article_nodes.dart';
import 'package:belog/features/blog/presentation/viewer/reader_app_bar.dart';
import 'package:belog/features/blog/presentation/viewer/viewer_article_body.dart';
import 'package:belog/router/read_aloud_route_observers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The loaded article: read-aloud wiring, follow-scroll, and the reading
/// surface.
///
/// Owns the full read-aloud lifecycle (document, controller, per-block keys,
/// route and app-lifecycle stops) so [BlogViewerPage] stays a route-level
/// widget: bloc wiring, loading/error states and bookkeeping.
class ViewerScaffold extends StatefulWidget {
  const ViewerScaffold({
    required this.blog,
    required this.onRequestLogin,
    required this.getRelatedArticles,
    required this.speechCoordinator,
    required this.readAloudPreferences,
    required this.readAloudRouteObserver,
  });

  final Blog blog;
  final VoidCallback onRequestLogin;
  final GetRelatedArticles getRelatedArticles;
  final SpeechCoordinator? speechCoordinator;
  final ReadAloudPreferences? readAloudPreferences;
  final RouteObserver<PageRoute<dynamic>>? readAloudRouteObserver;

  @override
  State<ViewerScaffold> createState() => _ViewerScaffoldState();
}

class _ViewerScaffoldState extends State<ViewerScaffold>
    with WidgetsBindingObserver, RouteAware {
  final ScrollController _scrollController = ScrollController();
  ReadAloudDocument? _document;
  ReadAloudController? _reader;
  List<GlobalKey> _blockKeys = const [];
  int _scrollRequest = 0;
  bool _prepared = false;

  Blog get blog => widget.blog;
  VoidCallback get onRequestLogin => widget.onRequestLogin;
  GetRelatedArticles get getRelatedArticles => widget.getRelatedArticles;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prepared) _prepareReader();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      final observers = widget.readAloudRouteObserver == null
          ? readAloudBranchObservers
          : [widget.readAloudRouteObserver!];
      for (final observer in observers) {
        observer.subscribe(this, route);
      }
    }
  }

  void _prepareReader() {
    _prepared = true;
    final structured = blog.document;
    final document = structured != null && structured.supported
        ? ReadAloudDocument.fromNodes(
            blog.title,
            structuredArticleNodes(structured),
          )
        : ReadAloudDocument.parse(blog.title, blog.content);
    // Rendering does not depend on whether a speech engine is available.
    _document = document;
    final coordinator = widget.speechCoordinator;
    final preferences = widget.readAloudPreferences;
    if (coordinator == null || preferences == null) return;
    _blockKeys = List.generate(document.blocks.length, (_) => GlobalKey());
    final reader = ReadAloudController(
      document: document,
      coordinator: coordinator,
      preferences: preferences,
      fallbackLanguage: Localizations.localeOf(context).languageCode,
      onFollowScroll: _followScroll,
    );
    _reader = reader;
    unawaited(reader.initialize());
  }

  @override
  void didUpdateWidget(covariant ViewerScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blog.id != blog.id ||
        oldWidget.blog.title != blog.title ||
        oldWidget.blog.content != blog.content ||
        oldWidget.blog.document != blog.document ||
        oldWidget.speechCoordinator != widget.speechCoordinator ||
        oldWidget.readAloudPreferences != widget.readAloudPreferences) {
      _reader?.dispose();
      _reader = null;
      _document = null;
      _blockKeys = const [];
      _scrollRequest++;
      _prepareReader();
    }
  }

  @override
  void didPushNext() {
    if (_reader?.phase != ReadAloudPhase.idle) _reader?.stop();
  }

  @override
  void didPop() {
    if (_reader?.phase != ReadAloudPhase.idle) _reader?.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        _reader?.phase != ReadAloudPhase.idle) {
      _reader?.stop();
    }
  }

  /// Follow the actual text position even inside a long paragraph. The
  /// document maps spoken offsets to the RenderParagraph's UTF-16 positions,
  /// accounting for inline-code/image WidgetSpans. Motion is disabled when
  /// the user's platform requests reduced animations.
  void _followScroll(int blockIndex, int spokenOffset) {
    final request = ++_scrollRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          request != _scrollRequest ||
          _reader?.follow != true ||
          _reader?.phase == ReadAloudPhase.idle ||
          !_scrollController.hasClients ||
          blockIndex >= _blockKeys.length) {
        return;
      }
      final targetContext = _blockKeys[blockIndex].currentContext;
      if (targetContext == null) return;
      final object = targetContext.findRenderObject();
      if (object == null) return;
      RenderParagraph? paragraph;
      void findParagraph(RenderObject child) {
        if (paragraph != null) return;
        if (child is RenderParagraph) {
          paragraph = child;
        } else {
          child.visitChildren(findParagraph);
        }
      }

      findParagraph(object);
      final render = paragraph;
      final scrollable = Scrollable.maybeOf(targetContext);
      final viewport = scrollable?.context.findRenderObject();
      if (render == null || viewport is! RenderBox || !viewport.hasSize) return;
      final plain = render.text.toPlainText(includeSemanticsLabels: false);
      final visualOffset = _document!.blocks[blockIndex]
          .visualOffset(spokenOffset)
          .clamp(0, plain.length);
      final caret = render.getOffsetForCaret(
        TextPosition(offset: visualOffset),
        Rect.zero,
      );
      final screenY = render.localToGlobal(caret).dy;
      final viewportY = viewport.localToGlobal(Offset.zero).dy;
      final relativeY = screenY - viewportY;
      final height = viewport.size.height;
      if (relativeY >= 80 && relativeY <= height - 72) return;
      final position = _scrollController.position;
      final destination = (position.pixels + relativeY - height * .38).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(destination);
      } else {
        unawaited(
          _scrollController.animateTo(
            destination,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollRequest++;
    for (final observer in readAloudBranchObservers) {
      observer.unsubscribe(this);
    }
    widget.readAloudRouteObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _reader?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ReaderAppBar(blog: blog, onRequestLogin: onRequestLogin),
      body: ViewerArticleBody(
        blog: blog,
        document: _document,
        reader: _reader,
        blockKeys: _blockKeys,
        scrollController: _scrollController,
        getRelatedArticles: getRelatedArticles,
        onRequestLogin: onRequestLogin,
      ),
    );
  }
}
