import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/category_paging.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class CategoriesState {
  const CategoriesState();
}

final class CategoriesInitial extends CategoriesState {
  const CategoriesInitial();
}

final class CategoriesLoading extends CategoriesState {
  const CategoriesLoading();
}

final class CategoriesFailure extends CategoriesState {
  const CategoriesFailure(this.failure);
  final Failure failure;
}

final class CategoriesSuccess extends CategoriesState {
  const CategoriesSuccess(this.categories);

  final List<CategoryRef> categories;

  bool get isEmpty => categories.isEmpty;

  /// The catalog is one page of at most `kCategoryListLimit`; a full page means
  /// the server may hold more, which the page says instead of implying the list
  /// is complete.
  bool get mayBeIncomplete => categories.length >= kCategoryListLimit;
}

/// The public category catalog, read once per page visit and kept in memory
/// only.
class CategoriesCubit extends Cubit<CategoriesState> {
  CategoriesCubit({required GetCategories getCategories})
    : _getCategories = getCategories,
      super(const CategoriesInitial());

  final GetCategories _getCategories;

  /// Drops a late answer when the catalog is reloaded or the page is closed.
  int _generation = 0;

  Future<void> load() async {
    if (isClosed) return;
    final generation = ++_generation;
    emit(const CategoriesLoading());
    final result = await _getCategories(NoParams());
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) => emit(CategoriesFailure(failure.forPresentation())),
      (categories) => emit(CategoriesSuccess(List.unmodifiable(categories))),
    );
  }
}
