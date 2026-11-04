import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/article_share.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controls.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/structured_article_nodes.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:belog/features/blog/presentation/widgets/related_articles_section.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:belog/router/read_aloud_route_observers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// Shows a single article.
///
/// The page is opened from cards with the already fetched article passed as
/// `extra`, and from deep links (or a restored process) with only [blogId];
/// [BlogViewerCubit] loads the article in that case. Like state lives in a
/// page-scoped [BlogLikedBloc] created with this route.
class BlogViewerPage extends StatefulWidget {
  final String blogId;

  /// Device-local reading history sink (issue #22); injectable for tests,
  /// resolved from the service locator when absent.
  final ReadingHistoryStore? historyStore;

  /// Related-articles rider loader (issue #19); same injection pattern.
  final GetRelatedArticles? getRelatedArticles;

  /// Injectable device speech and navigation boundaries for reader tests.
  final SpeechCoordinator? speechCoordinator;
  final ReadAloudPreferences? readAloudPreferences;
  final RouteObserver<PageRoute<dynamic>>? readAloudRouteObserver;

  const BlogViewerPage({
    super.key,
    required this.blogId,
    this.historyStore,
    this.getRelatedArticles,
    this.speechCoordinator,
    this.readAloudPreferences,
    this.readAloudRouteObserver,
  });

  @override
  State<BlogViewerPage> createState() => _BlogViewerPageState();
}

class _BlogViewerPageState extends State<BlogViewerPage> {
  /// Guards the history write so retries and like refreshes do not spam
  /// the store (the upsert would deduplicate anyway, but skip for free).
  String? _historyRecordedFor;

  @override
  void initState() {
    super.initState();
    _checkIfIsLiked();
  }

  void _checkIfIsLiked() {
    final appUserState = context.read<AppUserCubit>().state;

    if (appUserState is AppUserLoggedIn) {
      context.read<BlogLikedBloc>().add(
        GetIsBlogLiked(userId: appUserState.user.id, blogId: widget.blogId),
      );
    }
  }

  /// Reading history is device-local and per account (issue #22): only
  /// signed-in users are recorded, failures are swallowed (the reader must
  /// never break because a bookkeeping write failed).
  Future<void> _recordReadingHistory(String userId, Blog blog) async {
    if (_historyRecordedFor == '${userId}_${blog.id}') return;
    _historyRecordedFor = '${userId}_${blog.id}';
    try {
      final store =
          widget.historyStore ?? GetIt.instance<ReadingHistoryStore>();
      await store.record(userId: userId, blog: blog);
    } catch (e, stackTrace) {
      AppLogger.error(
        'recording the reading history failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _requestLogin() {
    final currentLocation = GoRouterState.of(context).uri.toString();
    context.push('/login?redirect=${Uri.encodeComponent(currentLocation)}');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BlogViewerCubit, BlogViewerState>(
      listener: (context, state) {
        if (state is BlogViewerFailure) {
          showSnackBar(context, localizedFailure(context.l10n, state.failure));
        } else if (state is BlogViewerLoaded) {
          final appUserState = context.read<AppUserCubit>().state;
          if (appUserState is AppUserLoggedIn) {
            context.read<BlogLikedBloc>().add(
              GetIsBlogLiked(
                userId: appUserState.user.id,
                blogId: state.blog.id,
              ),
            );
            _recordReadingHistory(appUserState.user.id, state.blog);
          }
        }
      },
      builder: (context, state) {
        if (state is BlogViewerLoaded) {
          return _ViewerScaffold(
            blog: state.blog,
            onRequestLogin: _requestLogin,
            getRelatedArticles:
                widget.getRelatedArticles ??
                GetIt.instance<GetRelatedArticles>(),
            speechCoordinator:
                widget.speechCoordinator ??
                (GetIt.instance.isRegistered<SpeechCoordinator>()
                    ? GetIt.instance<SpeechCoordinator>()
                    : null),
            readAloudPreferences:
                widget.readAloudPreferences ??
                (GetIt.instance.isRegistered<ReadAloudPreferences>()
                    ? GetIt.instance<ReadAloudPreferences>()
                    : null),
            readAloudRouteObserver: widget.readAloudRouteObserver,
          );
        }
        if (state is BlogViewerFailure) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(localizedFailure(context.l10n, state.failure)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        context.read<BlogViewerCubit>().load(widget.blogId),
                    child: Text(context.l10n.actionRetry),
                  ),
                ],
              ),
            ),
          );
        }
        return const Scaffold(body: Loader());
      },
    );
  }
}

class _ViewerScaffold extends StatefulWidget {
  const _ViewerScaffold({
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
  State<_ViewerScaffold> createState() => _ViewerScaffoldState();
}

class _ViewerScaffoldState extends State<_ViewerScaffold>
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
  void didUpdateWidget(covariant _ViewerScaffold oldWidget) {
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
    void openAuthor(String userId) {
      context.push(
        shellBranchLocation(
          GoRouterState.of(context).uri,
          '/author/${Uri.encodeComponent(userId)}',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Only share a canonical URL when WEB_BASE_URL is configured.
          if (articleWebUrl(blog.id) != null)
            IconButton(
              tooltip: context.l10n.shareArticleTooltip,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareArticle(title: blog.title, slug: blog.id),
            ),
          BlocConsumer<BlogLikedBloc, BlogLikedState>(
            listener: (context, state) {
              if (state is ToggleBlogLikeFailure) {
                showSnackBar(
                  context,
                  localizedFailure(context.l10n, state.failure),
                );
              }
            },
            builder: (context, state) {
              final isSaved = state.likedBlogs[blog.id] ?? false;
              return IconButton(
                tooltip: isSaved
                    ? context.l10n.unsaveTooltip
                    : context.l10n.saveTooltip,
                icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () {
                  final userState = context.read<AppUserCubit>().state;
                  if (userState is AppUserLoggedIn) {
                    context.read<BlogLikedBloc>().add(
                      ToggleBlogLike(
                        userId: userState.user.id,
                        blogId: blog.id,
                      ),
                    );
                  } else {
                    showSnackBar(context, context.l10n.signInRequired);
                    onRequestLogin();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NoWaveSpacing.page,
                    16,
                    NoWaveSpacing.page,
                    40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArticleReaderHeader(
                        blog: blog,
                        onAuthorTap: () => openAuthor(blog.posterId),
                        onTagTap: (tag) => openTagArticles(context, tag),
                        titleHighlight: _reader?.highlights.first,
                        titleKey: _blockKeys.isEmpty ? null : _blockKeys.first,
                      ),
                      const SizedBox(height: 32),
                      if (blog.document?.supported == false) ...[
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              context.l10n.articleUnsupportedDocument,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ),
                      ],
                      if (_reader != null)
                        ReadAloudControls(controller: _reader!),
                      MarkdownBody(
                        markdown: blog.content,
                        readAloudDocument: _document,
                        readAloudController: _reader,
                        readAloudBlockKeys: _blockKeys,
                        bodyStyle: NoWaveTypography.title(
                          context,
                          size: 18,
                        ).copyWith(fontWeight: FontWeight.w400, height: 1.9),
                        headingStyle: NoWaveTypography.title(context),
                      ),
                      const SizedBox(height: 30),
                      RelatedArticlesSection(
                        getRelatedArticles: getRelatedArticles,
                        slug: blog.id,
                        onOpenArticle: (related) => context.push(
                          shellBranchLocation(
                            GoRouterState.of(context).uri,
                            '/view/${Uri.encodeComponent(related.id)}',
                          ),
                          extra: related,
                        ),
                      ),
                      CommentsSection(
                        slug: blog.id,
                        onRequestLogin: onRequestLogin,
                        onOpenAuthor: openAuthor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
