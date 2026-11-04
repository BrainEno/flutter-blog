import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Everything filed under one tag (#106).
///
/// The tag arrives as the name the article stored; the bloc resolves it to
/// the server taxonomy. A name the server does not know is an explicit state,
/// never an unfiltered list.
class TagArticlesPage extends StatefulWidget {
  const TagArticlesPage({super.key, required this.tag});

  final String tag;

  @override
  State<TagArticlesPage> createState() => _TagArticlesPageState();
}

class _TagArticlesPageState extends State<TagArticlesPage> {
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
    context.read<TagArticlesBloc>().add(TagArticlesRequested(tag: widget.tag));
  }

  Future<void> _refresh() async {
    final bloc = context.read<TagArticlesBloc>();
    final settled = bloc.stream.firstWhere(
      (state) =>
          state is TagArticlesSuccess ||
          state is TagArticlesFailure ||
          state is TagArticlesUnknown,
    );
    bloc.add(TagArticlesRefreshed());
    await settled;
  }

  void _loadMore() {
    final state = context.read<TagArticlesBloc>().state;
    // A failed page waits for the reader to ask again: retrying from a
    // post-frame callback would hammer a server that is already unhappy.
    if (state is! TagArticlesSuccess) return;
    if (!state.hasMore || state.loadingMore || state.loadMoreFailure != null) {
      return;
    }
    if (_moreRequested) return;
    _moreRequested = true;
    context.read<TagArticlesBloc>().add(TagArticlesMoreRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final displayName = localizedTag(l10n, widget.tag);
    return Scaffold(
      appBar: AppBar(title: Text('#$displayName'), centerTitle: true),
      body: BlocListener<TagArticlesBloc, TagArticlesState>(
        // Any settled page may be followed by another one; only a failure
        // needs the reader's consent first (see [_loadMore]).
        listenWhen: (previous, current) =>
            current is TagArticlesSuccess && !current.loadingMore,
        listener: (context, state) => _moreRequested = false,
        child: BlocBuilder<TagArticlesBloc, TagArticlesState>(
          builder: (context, state) {
            if (state is TagArticlesLoading) {
              return Center(
                child: CircularProgressIndicator(
                  semanticsLabel: l10n.loadingArticles,
                ),
              );
            }
            if (state is TagArticlesUnknown) {
              return _status(
                NoWaveStatus(
                  message: l10n.tagUnknown(
                    localizedTag(
                      l10n,
                      state.tag.isEmpty ? widget.tag : state.tag,
                    ),
                  ),
                  actionLabel: l10n.actionRetry,
                  onAction: _request,
                ),
              );
            }
            if (state is TagArticlesFailure) {
              return _status(
                NoWaveStatus(
                  message: localizedFailure(l10n, state.failure),
                  actionLabel: l10n.actionRetry,
                  onAction: _request,
                ),
              );
            }
            if (state is TagArticlesSuccess) {
              if (state.isEmpty) {
                return _status(
                  NoWaveStatus(
                    message: l10n.tagArticlesEmpty(
                      localizedTag(l10n, state.tag.name),
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: _list(state),
              );
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
    children: [const SizedBox(height: 48), Center(child: status)],
  );

  Widget _list(TagArticlesSuccess state) {
    final l10n = context.l10n;
    final hasFooter =
        state.hasMore || state.loadingMore || state.loadMoreFailure != null;
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.page,
        NoWaveSpacing.large,
        NoWaveSpacing.page,
        NoWaveSpacing.section,
      ),
      itemCount: state.articles.length + (hasFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.articles.length) {
          final failed = state.loadMoreFailure;
          if (failed != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      localizedFailure(l10n, failed),
                      textAlign: TextAlign.center,
                      style: NoWaveTypography.meta(context),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadMore,
                      child: Text(l10n.actionRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state.loadingMore) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: l10n.loadingMoreArticles,
                ),
              ),
            );
          }
          // Ask for the next page once the footer is actually built.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadMore();
          });
          return const SizedBox(height: 32);
        }
        final Blog blog = state.articles[index];
        return _contentWidth(
          BlogCard(
            blog: blog,
            index: index + 1,
            labelAuthor: true,
            onTagTap: (tag) => openTagArticles(context, tag),
            onTap: () => context.push(
              shellBranchLocation(
                GoRouterState.of(context).uri,
                '/view/${Uri.encodeComponent(blog.id)}',
              ),
              extra: blog,
            ),
          ),
        );
      },
    );
  }

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );
}
