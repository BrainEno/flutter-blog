import 'dart:async';

import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart'
    show kMaxSearchResults;
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ImageIcon(AssetImage('assets/images/icon.png'), size: 30),
            SizedBox(width: 7),
            Text('Bottom Think'),
          ],
        ),
      ),
      // The search field is outside the fixed-height app bar so it can
      // grow naturally with the system font size.
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              maxLength: kMaxSearchQueryLength,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmitted,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          Expanded(
            child: BlocConsumer<BlogSearchBloc, BlogSearchState>(
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
                  return Center(child: Text(l10n.searchInitial));
                }
                if (state is BlogSearchLoading) {
                  return Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: l10n.searching,
                    ),
                  );
                }
                if (state is BlogSearchFailure) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.searchFailed(
                              localizedFailure(l10n, state.failure),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () =>
                                _onSubmitted(_searchController.text),
                            child: Text(l10n.actionRetry),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final blogs = (state as BlogSearchSuccess).blogs;
                if (blogs.isEmpty) {
                  return Center(child: Text(l10n.searchNoResults));
                }
                return ListView.separated(
                  itemCount: blogs.length + 1,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == blogs.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            blogs.length >= kMaxSearchResults
                                ? l10n.searchLimitReached(
                                    formatNumber(Localizations.localeOf(context), kMaxSearchResults),
                                  )
                                : l10n.searchNoMore,
                          ),
                        ),
                      );
                    }
                    final blog = blogs[index];
                    final name = blog.posterName?.trim().isNotEmpty == true
                        ? blog.posterName!
                        : l10n.anonymousAuthor;
                    return ListTile(
                      title: Text(blog.title),
                      subtitle: Text(l10n.posterLabel(name)),
                      leading: const Icon(Icons.article),
                      onTap: () =>
                          context.push('/search/view/${blog.id}', extra: blog),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
