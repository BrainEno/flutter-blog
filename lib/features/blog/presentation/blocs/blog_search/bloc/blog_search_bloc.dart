import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'blog_search_event.dart';
part 'blog_search_state.dart';

/// Upper bound on query length; longer input is truncated before hitting
/// the remote search.
const int kMaxSearchQueryLength = 50;

/// Title search. Concurrently dispatched searches are restartable: only the
/// response belonging to the latest request is emitted, so typing quickly
/// cannot render an older (stale) result set on top of a newer one.
class BlogSearchBloc extends Bloc<BlogSearchEvent, BlogSearchState> {
  final SearchBlogs _searchBlogs;

  int _generation = 0;

  BlogSearchBloc({required SearchBlogs searchBlogs})
    : _searchBlogs = searchBlogs,
      super(const BlogSearchInitial()) {
    on<SearchBlogsEvent>(_onSearchBlogs);
    on<SearchBlogsCleared>(_onSearchBlogsCleared);
  }

  Future<void> _onSearchBlogs(
    SearchBlogsEvent event,
    Emitter<BlogSearchState> emit,
  ) async {
    final query = event.query.trim();
    if (query.isEmpty) {
      add(const SearchBlogsCleared());
      return;
    }
    final generation = ++_generation;
    final boundedQuery = query.length > kMaxSearchQueryLength
        ? query.substring(0, kMaxSearchQueryLength)
        : query;
    emit(const BlogSearchLoading());
    final res = await _searchBlogs(SearchBlogsParams(query: boundedQuery));
    // A newer search (or a clear) superseded this one.
    if (generation != _generation) return;
    res.fold(
      (failure) => emit(BlogSearchFailure(error: failure.message)),
      (blogs) => emit(BlogSearchSuccess(blogs: blogs)),
    );
  }

  void _onSearchBlogsCleared(
    SearchBlogsCleared event,
    Emitter<BlogSearchState> emit,
  ) {
    _generation++;
    emit(const BlogSearchInitial());
  }
}
