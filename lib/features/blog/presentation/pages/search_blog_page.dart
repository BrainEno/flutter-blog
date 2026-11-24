import 'package:belog/core/design/components/no_wave_column.dart';
import 'package:belog/core/common/widgets/no_wave_masthead.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_end_mark.dart';
import 'package:belog/core/design/components/no_wave_entrance.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/search_debounce.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart'
    show kMaxSearchResults;
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/category_navigation.dart';
import 'package:belog/features/blog/presentation/search/recent_search_list.dart';
import 'package:belog/features/blog/presentation/search/recent_searches.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

class SearchBlogPage extends StatefulWidget {
  const SearchBlogPage({super.key, this.recentSearches});

  /// The recent searches to offer under the empty field; the app's own when
  /// null. Where none is registered, as in most widget tests, the page shows
  /// its plain prompt instead.
  final RecentSearches? recentSearches;

  @override
  State<SearchBlogPage> createState() => _SearchBlogPageState();
}

class _SearchBlogPageState extends State<SearchBlogPage> {
  final TextEditingController _searchController = TextEditingController();
  final SearchDebounce _debounce = SearchDebounce();
  RecentSearches? _recent;

  @override
  void initState() {
    super.initState();
    final locator = GetIt.instance;
    _recent =
        widget.recentSearches ??
        (locator.isRegistered<RecentSearches>()
            ? locator<RecentSearches>()
            : null);
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounce typing; the bloc also discards out-of-order responses.
  void _onQueryChanged() {
    _debounce.cancel();
    setState(() {});
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      context.read<BlogSearchBloc>().add(const SearchBlogsCleared());
      return;
    }
    _debounce(() {
      if (mounted) {
        context.read<BlogSearchBloc>().add(SearchBlogsEvent(query: query));
      }
    });
  }

  void _onSubmitted(String query) {
    _debounce.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      context.read<BlogSearchBloc>().add(const SearchBlogsCleared());
      return;
    }
    // Pressing search is what makes a query worth offering again; the
    // words typed on the way to it are not.
    _recent?.remember(trimmed);
    context.read<BlogSearchBloc>().add(SearchBlogsEvent(query: trimmed));
  }

  /// Runs a recent search again: the words go back in the field, and the
  /// keyboard steps aside for the results.
  void _searchAgain(String query) {
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    _onSubmitted(query);
  }

  void _clearRecent(RecentSearches recent) {
    final cleared = recent.queries;
    recent.clear();
    final l10n = context.l10n;
    showSnackBar(
      context,
      l10n.recentSearchesCleared,
      action: SnackBarAction(
        label: l10n.actionUndo,
        onPressed: () => recent.restore(cleared),
      ),
    );
  }

  Widget _initial(BuildContext context) {
    final prompt = _state(NoWaveStatus(message: context.l10n.searchInitial));
    final recent = _recent;
    if (recent == null) return prompt;
    return ListenableBuilder(
      listenable: recent,
      builder: (context, _) {
        final queries = recent.queries;
        if (queries.isEmpty) return prompt;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            NoWaveSpacing.page,
            NoWaveSpacing.small,
            NoWaveSpacing.page,
            NoWaveSpacing.large,
          ),
          sliver: SliverToBoxAdapter(
            child: _contentWidth(
              RecentSearchList(
                queries: queries,
                onSelect: _searchAgain,
                onRemove: recent.remove,
                onClear: () => _clearRecent(recent),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _contentWidth(Widget child) => NoWaveColumn(child: child);

  Widget _state(Widget child) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        child: _contentWidth(child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final foreground = Theme.of(context).colorScheme.onSurface;
    // Glyph on the column edge: the button's own inset sits after the word.
    final browse = TextButton.styleFrom(
      foregroundColor: foreground,
      padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.small),
      minimumSize: const Size(0, NoWaveSizes.tapTarget),
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: NoWaveColumn.inset(MediaQuery.sizeOf(context).width),
        title: const NoWaveMasthead(),
        actions: [
          IconButton(
            tooltip: l10n.offlineLibraryTooltip,
            icon: const Icon(Icons.folder_off_outlined),
            onPressed: () => context.push(RoutePaths.searchOfflineLibrary),
          ),
          const SizedBox(width: NoWaveSpacing.small),
        ],
      ),
      // The heading, field and results share one scroll view so they can all
      // reflow when the keyboard or a large text scale reduces the viewport.
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.page,
                NoWaveSpacing.large,
                NoWaveSpacing.page,
                NoWaveSpacing.medium,
              ),
              child: _contentWidth(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoWaveSectionHeading(
                      title: l10n.tabSearch,
                      companion: l10n.searchHeadingCompanion,
                    ),
                    const SizedBox(height: NoWaveSpacing.small),
                    // Both are browsing doors out of search: the editor's
                    // categories, and the public author directory. They
                    // start on the column edge under the heading, like the
                    // eyebrow above it; pushed to the right they read as
                    // stray buttons rather than part of the heading.
                    Wrap(
                      spacing: NoWaveSpacing.large,
                      children: [
                        TextButton.icon(
                          style: browse,
                          onPressed: () => openCategories(context),
                          icon: const Icon(
                            Icons.category_outlined,
                            size: NoWaveIconSize.inline,
                          ),
                          label: Text(l10n.categoriesBrowse),
                        ),
                        TextButton.icon(
                          style: browse,
                          onPressed: () =>
                              context.push(RoutePaths.searchAuthors),
                          icon: const Icon(
                            Icons.person_search_outlined,
                            size: NoWaveIconSize.inline,
                          ),
                          label: Text(l10n.authorSearchTitle),
                        ),
                      ],
                    ),
                    const SizedBox(height: NoWaveSpacing.small),
                    TextField(
                      controller: _searchController,
                      maxLength: kMaxSearchQueryLength,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _onSubmitted,
                      style: NoWaveTypography.title(
                        context,
                        size: NoWaveTypeScale.searchQuery,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.searchHint,
                        // The glyph sits on the column edge, where the
                        // heading and the rule under the field start.
                        prefixIcon: const Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: NoWaveSpacing.medium,
                          ),
                          child: Icon(Icons.search),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minHeight: NoWaveSizes.tapTarget,
                        ),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: l10n.clearSearch,
                                icon: const Icon(Icons.clear),
                                onPressed: _searchController.clear,
                              ),
                        counterText: '',
                        filled: false,
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: foreground,
                            width: NoWaveStroke.focus,
                          ),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: foreground,
                            width: NoWaveStroke.focus,
                          ),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AppPalette.orange,
                            width: NoWaveStroke.focus,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          BlocConsumer<BlogSearchBloc, BlogSearchState>(
            listener: (context, state) {
              if (state is BlogSearchFailure) {
                showSnackBar(
                  context,
                  l10n.searchFailed(localizedFailure(l10n, state.failure)),
                  duration: kShortSnackBarDuration,
                );
              }
            },
            builder: (context, state) {
              if (state is BlogSearchInitial) return _initial(context);
              if (state is BlogSearchLoading) {
                return _state(
                  NoWaveLoadingLabel(semanticLabel: l10n.searching),
                );
              }
              if (state is BlogSearchFailure) {
                return _state(
                  NoWaveStatus(
                    message: l10n.searchFailed(
                      localizedFailure(l10n, state.failure),
                    ),
                    actionLabel: l10n.actionRetry,
                    onAction: () => _onSubmitted(_searchController.text),
                  ),
                );
              }
              final blogs = (state as BlogSearchSuccess).blogs;
              if (blogs.isEmpty) {
                return _state(NoWaveStatus(message: l10n.searchNoResults));
              }
              // Every search arrives through the loading state, so each
              // result list gets a fresh scope and sets in once.
              return NoWaveEntranceScope(
                child: SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NoWaveSpacing.page,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == blogs.length) {
                        return _contentWidth(
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: NoWaveSpacing.large,
                            ),
                            child: NoWaveEndMark(
                              label: blogs.length >= kMaxSearchResults
                                  ? l10n.searchLimitReached(
                                      formatNumber(
                                        Localizations.localeOf(context),
                                        kMaxSearchResults,
                                      ),
                                    )
                                  : l10n.searchNoMore,
                            ),
                          ),
                        );
                      }
                      final blog = blogs[index];
                      return _contentWidth(
                        NoWaveEntrance(
                          index: index,
                          child: BlogCard(
                            blog: blog,
                            index: index + 1,
                            // The field's underline is the first rule.
                            ruled: index > 0,
                            labelAuthor: true,
                            onTagTap: (tag) => openTagArticles(context, tag),
                            onTap: () {
                              // Opening a result is the clearest sign the
                              // search found something, typed or submitted.
                              _recent?.remember(_searchController.text);
                              context.push(
                                RoutePaths.searchView(blog.id),
                                extra: blog,
                              );
                            },
                          ),
                        ),
                      );
                    }, childCount: blogs.length + 1),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
