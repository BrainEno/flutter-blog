import 'dart:async';

import 'package:belog/core/design/components/no_wave_running_head.dart';
import 'package:belog/core/design/components/no_wave_reading_progress.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_dock.dart';
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
    super.key,
    required this.blog,
    required this.onRequestLogin,
    required this.getRelatedArticles,
    required this.speechCoordinator,
    required this.readAloudPreferences,
    required this.readAloudRouteObserver,
  });

  final Blog blog;
  final VoidCallback onRequestLogin;
  final GetRelatedArticles? getRelatedArticles;
  final SpeechCoordinator? speechCoordinator;
  final ReadAloudPreferences? readAloudPreferences;
  final RouteObserver<PageRoute<dynamic>>? readAloudRouteObserver;

  @override
  State<ViewerScaffold> createState() => _ViewerScaffoldState();
}

class _ViewerScaffoldState extends State<ViewerScaffold>
    with WidgetsBindingObserver, RouteAware {
  final ScrollController _scrollController = ScrollController();

  /// The title, when read-aloud has not keyed it as its first block.
  final GlobalKey _titleKey = GlobalKey();

  /// Whether the title has scrolled under the app bar, so the running head
  /// shows.
  final ValueNotifier<bool> _runningHead = ValueNotifier(false);

  /// The full read-aloud controls, so the dock can tell when they are gone.
  final GlobalKey _controlsKey = GlobalKey();

  /// Whether the full controls have scrolled above the top of the page.
  final ValueNotifier<bool> _controlsPassed = ValueNotifier(false);

  /// Where the sentence being read is when the reader has taken the scroll
  /// away from the voice; null while the page follows it.
  ///
  /// Following used to win every time: each new word scrolled the page back
  /// to it, so a reader who scrolled up to the controls to stop the voice was
  /// pulled straight back down. A drag (or wheel, or the running head) now
  /// lets go of the voice. The page takes it up again when the reader asks
  /// (the dock's way back), when the spoken line comes back into view by
  /// itself, or when playback starts over.
  final ValueNotifier<VerticalDirection?> _voiceAway = ValueNotifier(null);

  /// A finger is on the article: never scroll under it.
  bool _dragging = false;
  ReadAloudPhase _lastPhase = ReadAloudPhase.idle;
  ReadAloudDocument? _document;
  ReadAloudController? _reader;
  List<GlobalKey> _blockKeys = const [];
  int _scrollRequest = 0;
  bool _prepared = false;

  Blog get blog => widget.blog;
  VoidCallback get onRequestLogin => widget.onRequestLogin;
  GetRelatedArticles? get getRelatedArticles => widget.getRelatedArticles;

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
    _lastPhase = reader.phase;
    reader.addListener(_onReaderChanged);
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
      _reader?.removeListener(_onReaderChanged);
      _reader?.dispose();
      _reader = null;
      _document = null;
      _blockKeys = const [];
      _scrollRequest++;
      _runningHead.value = false;
      _voiceAway.value = null;
      _prepareReader();
    }
  }

  /// Starting or stopping the voice hands the scroll back to it.
  void _onReaderChanged() {
    final phase = _reader?.phase ?? ReadAloudPhase.idle;
    final startedOrStopped =
        (phase == ReadAloudPhase.idle) != (_lastPhase == ReadAloudPhase.idle);
    _lastPhase = phase;
    if (startedOrStopped) _voiceAway.value = null;
  }

  /// The reader moved the page: stop following until they come back.
  void _letGo() {
    final reader = _reader;
    if (reader == null ||
        !reader.follow ||
        reader.phase == ReadAloudPhase.idle ||
        _voiceAway.value != null) {
      return;
    }
    // Cancels a follow scroll that was waiting for the next frame.
    _scrollRequest++;
    _voiceAway.value = VerticalDirection.down;
  }

  /// The dock's way back: follow again, and go to the voice now.
  void _returnToVoice() {
    _voiceAway.value = null;
    _reader?.revealPosition();
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
      final inView = relativeY >= 80 && relativeY <= height - 72;
      if (_voiceAway.value != null) {
        // The reader has the scroll. If they have brought the spoken line
        // back on screen themselves, follow again from here; otherwise only
        // note which way the voice is.
        if (inView && !_dragging) {
          _voiceAway.value = null;
        } else if (!inView) {
          _voiceAway.value = relativeY < 80
              ? VerticalDirection.up
              : VerticalDirection.down;
        }
        return;
      }
      if (inView) return;
      final position = _scrollController.position;
      final destination = (position.pixels + relativeY - height * .38).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      // A jump, not a scroll shortened to nothing: with less motion asked for,
      // the caret is placed where the voice already is.
      if (NoWaveMotionPolicy.reducesMotion(context)) {
        _scrollController.jumpTo(destination);
      } else {
        unawaited(
          _scrollController.animateTo(
            destination,
            duration: NoWaveMotion.normal,
            curve: NoWaveMotionPolicy.travel,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollRequest++;
    _reader?.removeListener(_onReaderChanged);
    for (final observer in readAloudBranchObservers) {
      observer.unsubscribe(this);
    }
    widget.readAloudRouteObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _reader?.dispose();
    _scrollController.dispose();
    _runningHead.dispose();
    _controlsPassed.dispose();
    _voiceAway.dispose();
    super.dispose();
  }

  /// Shows the running head once the title has passed under the app bar.
  /// Only the article's own scroll view counts, not a code block scrolling
  /// sideways inside it.
  bool _trackTitle(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final anchor = _blockKeys.isEmpty ? _titleKey : _blockKeys.first;
    _runningHead.value = NoWaveRunningHead.passed(
      anchor.currentContext,
      notification,
    );
    _controlsPassed.value = NoWaveRunningHead.passed(
      _controlsKey.currentContext,
      notification,
    );
    switch (notification) {
      case ScrollStartNotification(dragDetails: _?):
        _dragging = true;
        _letGo();
      case UserScrollNotification(direction: final direction)
          when direction != ScrollDirection.idle:
        _letGo();
      case ScrollEndNotification():
        _dragging = false;
      default:
        break;
    }
    return false;
  }

  /// The docked player: shown while the voice is on and either the full
  /// controls have scrolled away or the reader has left the voice behind.
  Widget? _dock() {
    final reader = _reader;
    if (reader == null) return null;
    return ListenableBuilder(
      listenable: Listenable.merge([reader, _controlsPassed, _voiceAway]),
      builder: (context, _) {
        final away = reader.follow ? _voiceAway.value : null;
        final show =
            reader.phase != ReadAloudPhase.idle &&
            (_controlsPassed.value || away != null);
        return AnimatedSize(
          duration: NoWaveMotionPolicy.resolve(context, NoWaveMotion.normal),
          curve: NoWaveMotionPolicy.travel,
          alignment: Alignment.topCenter,
          child: show
              ? ReadAloudDock(
                  controller: reader,
                  voiceAway: away,
                  onReturn: _returnToVoice,
                )
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ReaderAppBar(
        blog: blog,
        onRequestLogin: onRequestLogin,
        runningHead: _runningHead,
        onRunningHeadTap: () {
          _letGo();
          NoWaveRunningHead.toTop(context, _scrollController);
        },
      ),
      bottomNavigationBar: _dock(),
      body: NoWaveReadingProgress(
        child: NotificationListener<ScrollNotification>(
          onNotification: _trackTitle,
          child: ViewerArticleBody(
            blog: blog,
            document: _document,
            reader: _reader,
            blockKeys: _blockKeys,
            scrollController: _scrollController,
            getRelatedArticles: getRelatedArticles,
            onRequestLogin: onRequestLogin,
            titleKey: _titleKey,
            controlsKey: _controlsKey,
          ),
        ),
      ),
    );
  }
}
