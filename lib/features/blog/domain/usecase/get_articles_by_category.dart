import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:fpdart/fpdart.dart';

/// One page of a category's published articles. [offset] walks the server's
/// newest-first ordering; a short page is the end of the list.
class GetArticlesByCategory
    implements UseCase<List<Blog>, CategoryArticlesParams> {
  final CategoryRepository categoryRepository;
  const GetArticlesByCategory(this.categoryRepository);

  @override
  Future<Either<Failure, List<Blog>>> call(CategoryArticlesParams params) {
    return categoryRepository.getArticlesByCategory(
      params.slug,
      offset: params.offset,
    );
  }
}

class CategoryArticlesParams {
  final String slug;
  final int offset;

  CategoryArticlesParams({required this.slug, required this.offset});
}

/// Resolves a slug to the category the server knows, or null when it is gone.
class GetCategory implements UseCase<CategoryRef?, String> {
  final CategoryRepository categoryRepository;
  const GetCategory(this.categoryRepository);

  @override
  Future<Either<Failure, CategoryRef?>> call(String slug) {
    return categoryRepository.getCategory(slug);
  }
}
