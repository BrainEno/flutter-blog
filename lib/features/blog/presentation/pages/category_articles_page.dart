import 'package:belog/core/design/components/no_wave_column.dart';
import 'package:belog/core/design/components/no_wave_end_mark.dart';
import 'package:belog/core/design/components/no_wave_list_note.dart';
import 'package:belog/core/design/components/no_wave_refresh.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_entrance.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/features/blog/presentation/widgets/blog_feed_skeleton.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

/// Everything filed under one category.
///
/// The category arrives as a slug; the bloc resolves the name the server uses
/// in the current content language. A slug the server does not know is an
/// explicit state, never an unfiltered list.
class CategoryArticlesPage extends StatefulWidget {
  const CategoryArticlesPage({super.key, required this.slug, this.knownName});

  final String slug;

  /// The name the caller already had, so the title does not have to wait for
  /// the lookup. Null for a deep link.
  final String? knownName;

  @override
  State<CategoryArticlesPage> createState() => _CategoryArticlesPageState();
}

class _CategoryArticlesPageState extends State<CategoryArticlesPage> {
  final ScrollController _scrollController = ScrollController();
  bool _moreRequested = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _request() {
    _moreRequested = false;
    context.read<CategoryArticlesBloc>().add(
      CategoryArticlesRequested(slug: widget.slug),
    );
  }

  Future<void> _refresh() async {
    final bloc = context.read<CategoryArticlesBloc>();
    final settled = bloc.stream.firstWhere(
      (state) =>
          state is CategoryArticlesSuccess ||
          state is CategoryArticlesFailure ||
          state is CategoryArticlesNotFound,
    );
    bloc.add(CategoryArticlesRefreshed());
    await settled;
  }

  void _loadMore() {
    final state = context.read<CategoryArticlesBloc>().state;
    // A failed page waits for the reader to ask again: retrying from a
    // post-frame callback would hammer a server that is already unhappy.
    if (state is! CategoryArticlesSuccess) return;
    if (!state.hasMore || state.loadingMore || state.loadMoreFailure != null) {
      return;
    }
    if (_moreRequested) return;
    _moreRequested = true;
    context.read<CategoryArticlesBloc>().add(CategoryArticlesMoreRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<CategoryArticlesBloc, CategoryArticlesState>(
          buildWhen: (previous, current) =>
              current is CategoryArticlesSuccess ||
              previous is CategoryArticlesSuccess,
          builder: (context, state) {
            final known = widget.knownName?.trim() ?? '';
            if (state is CategoryArticlesSuccess) {
              return Text(state.category.name);
            }
            if (known.isNotEmpty) return Text(known);
            return Text(l10n.categoryArticlesTitle);
          },
        ),
      ),
      body: BlocListener<CategoryArticlesBloc, CategoryArticlesState>(
        // Any settled page may be followed by another one; only a failure
        // needs the reader's consent first (see [_loadMore]).
        listenWhen: (previous, current) =>
            current is CategoryArticlesSuccess && !current.loadingMore,
        listener: (context, state) => _moreRequested = false,
        child: BlocBuilder<CategoryArticlesBloc, CategoryArticlesState>(
          builder: (context, state) {
            if (state is CategoryArticlesLoading ||
                state is CategoryArticlesInitial) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  NoWaveSpacing.page,
                  NoWaveSpacing.large,
                  NoWaveSpacing.page,
                  NoWaveSpacing.section,
                ),
                children: [
                  _contentWidth(
                    BlogFeedSkeleton(
                      showFeatured: false,
                      semanticLabel: l10n.loadingArticles,
                    ),
                  ),
                ],
              );
            }
            if (state is CategoryArticlesNotFound) {
              return _status(
                NoWaveStatus(
                  message: l10n.categoryNotFound,
                  actionLabel: l10n.actionRetry,
                  onAction: _request,
                ),
              );
            }
            if (state is CategoryArticlesFailure) {
              return _status(
                NoWaveStatus(
                  message: localizedFailure(l10n, state.failure),
                  actionLabel: l10n.actionRetry,
                  onAction: _request,
                ),
              );
            }
            if (state is CategoryArticlesSuccess) {
              if (state.isEmpty) {
                return _status(
                  NoWaveStatus(
                    message: l10n.categoryArticlesEmpty(state.category.name),
                  ),
                );
              }
              return NoWaveRefresh(onRefresh: _refresh, child: _list(state));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _status(Widget status) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(NoWaveSpacing.page),
    children: [
      const SizedBox(height: NoWaveSizes.emptyStateOffset),
      Center(child: status),
    ],
  );

  Widget _list(CategoryArticlesSuccess state) {
    final l10n = context.l10n;
    // The page is one list; its first screen sets in once, and a refresh or
    // next page holds still.
    return NoWaveEntranceScope(
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          NoWaveSpacing.page,
          NoWaveSpacing.large,
          NoWaveSpacing.page,
          NoWaveSpacing.section,
        ),
        // Always a footer: the next page, its failure, or - once the list
        // is complete - the end mark, so the last card reads as last.
        itemCount: state.articles.length + 1,
        itemBuilder: (context, index) {
          if (index == state.articles.length) {
            final failed = state.loadMoreFailure;
            if (failed != null) {
              return _contentWidth(
                NoWaveListNote(
                  message: localizedFailure(l10n, failed),
                  actionLabel: l10n.actionRetry,
                  onAction: _loadMore,
                  live: true,
                ),
              );
            }
            if (state.loadingMore) {
              return Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.medium),
                child: Center(
                  child: NoWaveLoadingLabel(
                    semanticLabel: l10n.loadingMoreArticles,
                    compact: true,
                  ),
                ),
              );
            }
            if (!state.hasMore) {
              return _contentWidth(
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: NoWaveSpacing.large,
                  ),
                  child: NoWaveEndMark(label: l10n.feedNoMore),
                ),
              );
            }
            // Ask for the next page once the footer is actually built.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadMore();
            });
            return const SizedBox(height: NoWaveSpacing.section);
          }
          final Blog blog = state.articles[index];
          return _contentWidth(
            NoWaveEntrance(
              index: index,
              child: BlogCard(
                blog: blog,
                index: index + 1,
                labelAuthor: true,
                onTagTap: (tag) => openTagArticles(context, tag),
                onTap: () => context.push(
                  shellBranchLocation(
                    GoRouterState.of(context).uri,
                    RoutePaths.view(blog.id),
                  ),
                  extra: blog,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _contentWidth(Widget child) => NoWaveColumn(child: child);
}
