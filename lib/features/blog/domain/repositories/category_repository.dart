import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:fpdart/fpdart.dart';

/// Public category browsing: the catalog and one category's articles.
///
/// Both reads are online-only and anonymous, and nothing is persisted: the
/// server owns the names (they are translated per content language) and the
/// membership of a category.
abstract interface class CategoryRepository {
  /// The catalog, ordered by name as the server sorts it.
  ///
  /// At most `kCategoryListLimit` entries are asked for; a full page means the
  /// catalog may be truncated, which the page has to say rather than hide.
  Future<Either<Failure, List<CategoryRef>>> listCategories();

  /// One category by slug, or null when the server has no such category.
  ///
  /// Null is an explicit answer, never an error: a category removed since the
  /// link was made is a normal outcome for a browsable page.
  Future<Either<Failure, CategoryRef?>> getCategory(String slug);

  /// One page of a category's published articles, newest first.
  Future<Either<Failure, List<Blog>>> getArticlesByCategory(
    String slug, {
    required int offset,
  });
}
