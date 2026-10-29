import 'dart:async';

import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// How long the page waits after a keystroke before dispatching a search.
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

  /// Debounced search-as-you-type: only the last query within the debounce
  /// window is dispatched; the bloc additionally discards out-of-order
  /// responses.
  void _onQueryChanged() {
    _debounce?.cancel();
    // Rebuild so the clear button appears/disappears with the text.
    setState(() {});
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      // Clear immediately; no point waiting out the debounce.
      context.read<BlogSearchBloc>().add(const SearchBlogsCleared());
      return;
    }
    _debounce = Timer(_kSearchDebounce, () {
      if (!mounted) return;
      context.read<BlogSearchBloc>().add(SearchBlogsEvent(query: query));
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 125,
        title: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ImageIcon(AssetImage('assets/images/icon.png'), size: 30),
                SizedBox(width: 7),
                const Text('Bottom Think'),
              ],
            ),
            const SizedBox(height: 10),
            // Bound the query length; the bloc truncates defensively too.
            TextField(
              controller: _searchController,
              maxLength: kMaxSearchQueryLength,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmitted,
              decoration: InputDecoration(
                hintText: '搜索标题...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      ),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
      body: BlocConsumer<BlogSearchBloc, BlogSearchState>(
        listener: (context, state) {
          if (state is BlogSearchFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text('搜索失败：${state.error}'),
                  duration: const Duration(seconds: 2),
                ),
              );
          }
        },
        builder: (context, state) {
          if (state is BlogSearchInitial) {
            return const Center(child: Text('输入关键词，搜索你感兴趣的文章'));
          }
          if (state is BlogSearchLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is BlogSearchFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('搜索失败：${state.error}'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _onSubmitted(_searchController.text),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final blogs = (state as BlogSearchSuccess).blogs;
          if (blogs.isEmpty) {
            return const Center(child: Text('暂时没有相关结果'));
          }
          return ListView.separated(
            itemCount: blogs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final blog = blogs[index];
              return ListTile(
                title: Text(
                  blog.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text('发布者：${blog.posterName ?? ''}'),
                leading: const Icon(Icons.article),
                onTap: () {
                  context.push('/search/view/${blog.id}', extra: blog);
                },
              );
            },
          );
        },
      ),
    );
  }
}
