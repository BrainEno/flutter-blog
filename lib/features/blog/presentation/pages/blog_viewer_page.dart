import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/views/article_view_recorder.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_controller.dart';
import 'package:belog/features/blog/presentation/viewer/viewer_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

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

  /// Optional, best-effort view telemetry; injectable for reader tests.
  final RecordArticleView? recordArticleView;

  /// Injectable device speech and navigation boundaries for reader tests.
  final SpeechCoordinator? speechCoordinator;
  final ReadAloudPreferences? readAloudPreferences;
  final RouteObserver<PageRoute<dynamic>>? readAloudRouteObserver;

  /// The reader's text size; injectable for tests, resolved from the service
  /// locator when absent.
  final ReaderTextSizeController? textSize;

  const BlogViewerPage({
    super.key,
    required this.blogId,
    this.historyStore,
    this.getRelatedArticles,
    this.recordArticleView,
    this.speechCoordinator,
    this.readAloudPreferences,
    this.readAloudRouteObserver,
    this.textSize,
  });

  @override
  State<BlogViewerPage> createState() => _BlogViewerPageState();
}

class _BlogViewerPageState extends State<BlogViewerPage> {
  /// Guards the history write so retries and like refreshes do not spam
  /// the store (the upsert would deduplicate anyway, but skip for free).
  String? _historyRecordedFor;
  final Set<String> _viewRecorded = {};
  final Set<String> _viewScheduled = {};

  /// Where the reader left this article last time, read once when the page
  /// opens; null until known, or when there is nothing to pick up.
  double? _resumeAt;

  /// The position last written, so a scroll that ends where it began does
  /// not write again.
  double? _savedProgress;

  @override
  void initState() {
    super.initState();
    _checkIfIsLiked();
    unawaited(_loadResumePoint());
    // Opened from a card, the article is already here: the cubit starts
    // loaded and the listener below never hears a change, so the history
    // entry was only ever written for deep links. Record it now.
    final state = context.read<BlogViewerCubit>().state;
    final userId = _signedInUserId;
    if (state is BlogViewerLoaded && userId != null) {
      unawaited(_recordReadingHistory(userId, state.blog));
    }
  }

  ReadingHistoryStore? get _store {
    if (widget.historyStore case final store?) return store;
    final locator = GetIt.instance;
    return locator.isRegistered<ReadingHistoryStore>()
        ? locator<ReadingHistoryStore>()
        : null;
  }

  String? get _signedInUserId {
    final state = context.read<AppUserCubit>().state;
    return state is AppUserLoggedIn && state.user.id.isNotEmpty
        ? state.user.id
        : null;
  }

  /// Positions are kept with the reading history, so - like it - only for a
  /// signed-in reader, and a failed read only means opening at the top.
  Future<void> _loadResumePoint() async {
    final userId = _signedInUserId;
    final store = _store;
    if (userId == null || store == null) return;
    try {
      final progress = await store.progressOf(
        userId: userId,
        blogId: widget.blogId,
      );
      if (!mounted || progress == null) return;
      _savedProgress = progress;
      setState(() => _resumeAt = progress);
    } catch (e, stackTrace) {
      AppLogger.error(
        'reading the resume point failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveProgress(double progress) async {
    final userId = _signedInUserId;
    final store = _store;
    if (userId == null || store == null) return;
    final saved = _savedProgress;
    if (saved != null && (saved - progress).abs() < 0.01) return;
    _savedProgress = progress;
    try {
      await store.saveProgress(
        userId: userId,
        blogId: widget.blogId,
        progress: progress,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'saving the reading position failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
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
    final store = _store;
    if (store == null) return;
    try {
      await store.record(userId: userId, blog: blog);
    } catch (e, stackTrace) {
      AppLogger.error(
        'recording the reading history failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Schedule only after a frame displaying this edition completed. The initial
  /// state may already be loaded (card navigation), so a state listener alone
  /// would miss it. Retries/rebuilds on this route do not send another beacon.
  void _scheduleView(Blog blog) {
    if (blog.isDraft ||
        blog.id.isEmpty ||
        !const {'zh-CN', 'zh-TW', 'en'}.contains(blog.locale)) {
      return;
    }
    final key = '${blog.id}\u0000${blog.locale}';
    if (_viewRecorded.contains(key) || !_viewScheduled.add(key)) return;
    PreparedArticleView? operation;
    try {
      final recorder =
          widget.recordArticleView ??
          (GetIt.instance.isRegistered<RecordArticleView>()
              ? GetIt.instance<RecordArticleView>()
              : null);
      operation = recorder?.prepare(blog);
    } catch (_) {
      _viewScheduled.remove(key);
      return;
    }
    final prepared = operation;
    if (prepared == null) {
      _viewScheduled.remove(key);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewScheduled.remove(key);
      if (!mounted) return;
      final current = context.read<BlogViewerCubit>().state;
      if (current is! BlogViewerLoaded ||
          current.blog.id != blog.id ||
          current.blog.locale != blog.locale ||
          current.blog.isDraft) {
        return;
      }
      _viewRecorded.add(key);
      _sendView(prepared);
    });
  }

  Future<void> _sendView(PreparedArticleView operation) async {
    try {
      await operation();
    } catch (_) {
      // Optional telemetry must not change content, trigger a snackbar, or
      // retry after an uncertain network outcome.
    }
  }

  void _requestLogin() {
    final currentLocation = GoRouterState.of(context).uri.toString();
    context.push(RoutePaths.withRedirect(RoutePaths.login, currentLocation));
  }

  /// The related-articles use case is an optional decoration, not part of
  /// reading the article: an unregistered one must hide that section rather
  /// than throw a red screen over the whole page. The registration itself is
  /// kept from drifting by `service_locator_registration_test`.
  GetRelatedArticles? _relatedArticles() {
    if (widget.getRelatedArticles != null) return widget.getRelatedArticles;
    return GetIt.instance.isRegistered<GetRelatedArticles>()
        ? GetIt.instance<GetRelatedArticles>()
        : null;
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
          _scheduleView(state.blog);
          return ViewerScaffold(
            blog: state.blog,
            onRequestLogin: _requestLogin,
            getRelatedArticles: _relatedArticles(),
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
            resumeAt: _resumeAt,
            onProgress: _saveProgress,
            textSize:
                widget.textSize ??
                (GetIt.instance.isRegistered<ReaderTextSizeController>()
                    ? GetIt.instance<ReaderTextSizeController>()
                    : null),
          );
        }
        if (state is BlogViewerFailure) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                child: NoWaveStatus(
                  message: localizedFailure(context.l10n, state.failure),
                  actionLabel: context.l10n.actionRetry,
                  onAction: () =>
                      context.read<BlogViewerCubit>().load(widget.blogId),
                ),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: NoWaveLoadingLabel()));
      },
    );
  }
}
