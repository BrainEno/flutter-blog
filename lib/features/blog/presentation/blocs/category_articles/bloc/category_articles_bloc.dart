import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/category_paging.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_category.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'category_articles_event.dart';
part 'category_articles_state.dart';

/// Browses one category: resolve its name once, then walk its articles by
/// offset.
///
/// A slug the server does not know, and a category that exists with nothing
/// filed under it, are different states on purpose: collapsing them into an
/// empty list is how a browsing page ends up showing unrelated content.
class CategoryArticlesBloc
    extends Bloc<CategoryArticlesEvent, CategoryArticlesState> {
  final GetCategory _getCategory;
  final GetArticlesByCategory _getArticlesByCategory;

  /// The address the page was opened with.
  String? _slug;

  /// The resolved category, reused by refresh and load-more.
  CategoryRef? _category;

  CategoryArticlesBloc({
    required GetCategory getCategory,
    required GetArticlesByCategory getArticlesByCategory,
  }) : _getCategory = getCategory,
       _getArticlesByCategory = getArticlesByCategory,
       super(CategoryArticlesInitial()) {
    on<CategoryArticlesRequested>(_onRequested);
    on<CategoryArticlesRefreshed>(_onRefreshed);
    on<CategoryArticlesMoreRequested>(_onMoreRequested);
  }

  Future<void> _onRequested(
    CategoryArticlesRequested event,
    Emitter<CategoryArticlesState> emit,
  ) async {
    final slug = event.slug.trim();
    if (slug.isEmpty) {
      emit(CategoryArticlesNotFound(slug: event.slug));
      return;
    }
    _slug = slug;
    _category = null;
    await _loadFirstPage(emit);
  }

  Future<void> _onRefreshed(
    CategoryArticlesRefreshed event,
    Emitter<CategoryArticlesState> emit,
  ) async {
    if (_slug == null) return;
    await _loadFirstPage(emit);
  }

  Future<void> _loadFirstPage(Emitter<CategoryArticlesState> emit) async {
    final slug = _slug;
    if (slug == null) return;
    emit(CategoryArticlesLoading());

    // Reuse the resolved category on refresh; a slug's name only changes if an
    // editor renames it, and a pull-to-refresh is not the moment to check.
    var category = _category;
    if (category == null) {
      final resolved = await _getCategory(slug);
      CategoryRef? found;
      Failure? resolveFailure;
      resolved.fold((failure) => resolveFailure = failure, (value) {
        found = value;
      });
      final failure = resolveFailure;
      if (failure != null) {
        emit(CategoryArticlesFailure(failure: failure.forPresentation()));
        return;
      }
      final resolvedCategory = found;
      if (resolvedCategory == null) {
        emit(CategoryArticlesNotFound(slug: slug));
        return;
      }
      category = resolvedCategory;
      _category = resolvedCategory;
    }

    final res = await _getArticlesByCategory(
      CategoryArticlesParams(slug: slug, offset: 0),
    );
    res.fold(
      (failure) => emit(_notFoundOrFailure(failure, slug)),
      (articles) => emit(
        CategoryArticlesSuccess(
          category: category!,
          articles: articles,
          hasMore: articles.length >= kCategoryPageSize,
        ),
      ),
    );
  }

  Future<void> _onMoreRequested(
    CategoryArticlesMoreRequested event,
    Emitter<CategoryArticlesState> emit,
  ) async {
    final current = state;
    if (current is! CategoryArticlesSuccess) return;
    if (!current.hasMore || current.loadingMore) return;

    emit(current.copyWith(loadingMore: true, loadMoreFailure: null));
    final res = await _getArticlesByCategory(
      CategoryArticlesParams(
        slug: current.category.slug,
        offset: current.articles.length,
      ),
    );
    res.fold(
      (failure) => emit(
        current.copyWith(
          loadingMore: false,
          loadMoreFailure: failure.forPresentation(),
        ),
      ),
      (more) {
        // Offset paging can repeat a row when something is published while the
        // reader scrolls; ids are stable, so drop what is already shown.
        final seen = current.articles.map((blog) => blog.id).toSet();
        final added = more.where((blog) => seen.add(blog.id)).toList();
        emit(
          CategoryArticlesSuccess(
            category: current.category,
            articles: [...current.articles, ...added],
            hasMore: more.length >= kCategoryPageSize,
          ),
        );
      },
    );
  }

  /// A category that vanished between reading its name and its articles is the
  /// same state as one that never existed: say so rather than show an empty
  /// list.
  CategoryArticlesState _notFoundOrFailure(Failure failure, String slug) {
    if (failure.code == 'category.notFound') {
      return CategoryArticlesNotFound(slug: slug);
    }
    return CategoryArticlesFailure(failure: failure.forPresentation());
  }
}
