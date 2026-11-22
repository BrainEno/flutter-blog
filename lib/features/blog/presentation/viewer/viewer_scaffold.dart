import 'dart:async';

import 'package:belog/core/design/components/no_wave_running_head.dart';
import 'package:belog/core/design/components/no_wave_reading_progress.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_dock.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/read_aloud/structured_article_nodes.dart';
import 'package:belog/features/blog/presentation/viewer/reader_app_bar.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_controller.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_sheet.dart';
import 'package:belog/features/blog/presentation/viewer/resume_reading_slip.dart';
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
    this.resumeAt,
    this.onProgress,
    this.textSize,
  });

  /// The reader's text size, shared by every article; null hides the
  /// text-size button and sets the text at the standard size.
  final ReaderTextSizeController? textSize;

  /// Where the reader left this article last time, as a share of its text;
  /// the page offers to go back there. Null when there is nothing to offer.
  final double? resumeAt;

  /// Told where the reader is, as a share of the text, whenever a scroll
  /// comes to rest.
  final ValueChanged<double>? onProgress;

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

  /// The end mark, for measuring how much of the text is behind the reader.
  final GlobalKey _endKey = GlobalKey();

  /// Whether the offer to pick up where the reader left off is withdrawn:
  /// taken, or overtaken by the reader scrolling on their own.
  final ValueNotifier<bool> _resumeDone = ValueNotifier(false);

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
    widget.textSize?.addListener(_onTextSizeChanged);
  }

  /// Reflowing the text at a new size moves every line under the reader's
  /// eye: keep the same share of the text behind them, so they are still at
  /// the paragraph they were reading.
  void _onTextSizeChanged() {
    final kept = _progress();
    setState(() {});
    if (kept == null || kept == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final span = _textSpan();
      if (span == null) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (kept * span).clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
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
    if (oldWidget.textSize != widget.textSize) {
      oldWidget.textSize?.removeListener(_onTextSizeChanged);
      widget.textSize?.addListener(_onTextSizeChanged);
    }
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
    widget.textSize?.removeListener(_onTextSizeChanged);
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
    _resumeDone.dispose();
    _voiceAway.dispose();
    super.dispose();
  }

  /// How far the page can scroll before the end mark is on screen: the
  /// stretch the reader has to travel through the text. Null before layout,
  /// or when the whole article fits on one screen and there is nothing to
  /// pick up. The related reading and comments under the text are left out:
  /// they load late and would move every saved position.
  double? _textSpan() {
    if (!_scrollController.hasClients) return null;
    final box = _endKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final position = _scrollController.position;
    final span =
        viewport.getOffsetToReveal(box, 0).offset - position.viewportDimension;
    return span > position.viewportDimension / 2 ? span : null;
  }

  /// The share of the text behind the reader, from 0 to 1.
  double? _progress() {
    final span = _textSpan();
    if (span == null) return null;
    return (_scrollController.position.pixels / span).clamp(0.0, 1.0);
  }

  /// Whether [at] is worth an offer: far enough in to have been reading,
  /// short of the end.
  static bool _resumable(double? at) =>
      at != null &&
      at >= ReadingProgress.started &&
      at < ReadingProgress.finished;

  /// Goes back to where the reader left off. A glide rather than a cut, so
  /// the reader sees they have been carried down the same page; a jump when
  /// less motion is asked for.
  void _resume() {
    _resumeDone.value = true;
    final span = _textSpan();
    final at = widget.resumeAt;
    if (span == null || at == null) return;
    final position = _scrollController.position;
    final target = (at * span).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (NoWaveMotionPolicy.reducesMotion(context)) {
      _scrollController.jumpTo(target);
    } else {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: NoWaveMotion.resume,
          curve: NoWaveMotionPolicy.curve,
        ),
      );
    }
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
        if (_progress() case final progress?) {
          widget.onProgress?.call(progress);
          // Read on past the place by hand, and the offer has nothing left
          // to give.
          if (!_resumeDone.value &&
              progress >= (widget.resumeAt ?? 0) - ReadingProgress.started) {
            _resumeDone.value = true;
          }
        }
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

  /// The offer to pick up where the reader left off: an ink slip at the
  /// foot of the page with the share already read. It rises in once, and
  /// leaves when taken, when the reader scrolls past the place themselves,
  /// or while the voice is on and the dock owns the bottom of the screen.
  Widget _resumeOffer() {
    final at = widget.resumeAt;
    if (!_resumable(at)) return const SizedBox.shrink();
    final reader = _reader;
    return ListenableBuilder(
      listenable: Listenable.merge([_resumeDone, if (reader != null) reader]),
      builder: (context, _) {
        final show =
            !_resumeDone.value &&
            (reader == null || reader.phase == ReadAloudPhase.idle);
        return Center(
          child: AnimatedSwitcher(
            duration: NoWaveMotionPolicy.resolve(context, NoWaveMotion.slow),
            switchInCurve: NoWaveMotionPolicy.curve,
            switchOutCurve: NoWaveMotionPolicy.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, NoWaveMotion.runningHeadRise),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: show
                ? ResumeReadingSlip(
                    key: const ValueKey('resume-reading'),
                    progress: at!,
                    onTap: _resume,
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSize = widget.textSize;
    return Scaffold(
      appBar: ReaderAppBar(
        onTextSize: textSize == null
            ? null
            : () => ReaderTextSizeSheet.show(context, textSize),
        blog: blog,
        onRequestLogin: onRequestLogin,
        runningHead: _runningHead,
        onRunningHeadTap: () {
          _letGo();
          NoWaveRunningHead.toTop(context, _scrollController);
        },
      ),
      bottomNavigationBar: _dock(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          NoWaveReadingProgress(
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
                endKey: _endKey,
                textFactor: textSize == null
                    ? 1
                    : readerTextFactor(textSize.value),
              ),
            ),
          ),
          PositionedDirectional(
            start: NoWaveSpacing.page,
            end: NoWaveSpacing.page,
            bottom: NoWaveSpacing.large,
            child: _resumeOffer(),
          ),
        ],
      ),
    );
  }
}
