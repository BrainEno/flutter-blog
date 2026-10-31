import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_masthead.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart'
    show kMaxSearchResults;
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/widgets/blog_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

const Duration _kSearchDebounce = Duration(milliseconds: 300);

class SearchBlogPage extends StatefulWidget {
  const SearchBlogPage({super.key});

  @override
  State<SearchBlogPage> createState() => _SearchBlogPageState();
}

class _SearchBlogPageState extends State<SearchBlogPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounce typing; the bloc also discards out-of-order responses.
  void _onQueryChanged() {
    _debounce?.cancel();
    setState(() {});
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      context.read<BlogSearchBloc>().add(const SearchBlogsCleared());
      return;
    }
    _debounce = Timer(_kSearchDebounce, () {
      if (mounted) {
        context.read<BlogSearchBloc>().add(SearchBlogsEvent(query: query));
      }
    });
  }

  void _onSubmitted(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      context.read<BlogSearchBloc>().add(const SearchBlogsCleared());
      return;
    }
    context.read<BlogSearchBloc>().add(SearchBlogsEvent(query: trimmed));
  }

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );

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
    return Scaffold(
      appBar: AppBar(title: const NoWaveMasthead()),
      // The heading, field and results share one scroll view so they can all
      // reflow when the keyboard or a large text scale reduces the viewport.
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.page,
                24,
                NoWaveSpacing.page,
                16,
              ),
              child: _contentWidth(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoWaveSectionHeading(
                      title: l10n.tabSearch,
                      companion: l10n.searchHeadingCompanion,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      maxLength: kMaxSearchQueryLength,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _onSubmitted,
                      style: NoWaveTypography.title(context, size: 24),
                      decoration: InputDecoration(
                        labelText: l10n.searchHint,
                        prefixIcon: const Icon(Icons.search),
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
                          borderSide: BorderSide(color: foreground, width: 2),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: foreground, width: 2),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AppPalette.orange,
                            width: 3,
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
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.searchFailed(
                          localizedFailure(l10n, state.failure),
                        ),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
              }
            },
            builder: (context, state) {
              if (state is BlogSearchInitial) {
                return _state(NoWaveStatus(message: l10n.searchInitial));
              }
              if (state is BlogSearchLoading) {
                return _state(
                  CircularProgressIndicator(semanticsLabel: l10n.searching),
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
              return SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NoWaveSpacing.page,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index == blogs.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            blogs.length >= kMaxSearchResults
                                ? l10n.searchLimitReached(
                                    formatNumber(
                                      Localizations.localeOf(context),
                                      kMaxSearchResults,
                                    ),
                                  )
                                : l10n.searchNoMore,
                            style: NoWaveTypography.meta(context),
                          ),
                        ),
                      );
                    }
                    final blog = blogs[index];
                    return _contentWidth(
                      BlogCard(
                        blog: blog,
                        index: index + 1,
                        labelAuthor: true,
                        onTap: () => context.push(
                          '/search/view/${blog.id}',
                          extra: blog,
                        ),
                      ),
                    );
                  }, childCount: blogs.length + 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
