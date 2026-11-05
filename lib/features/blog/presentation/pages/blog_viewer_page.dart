import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/viewer/viewer_scaffold.dart';
import 'package:flutter/material.dart';
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
