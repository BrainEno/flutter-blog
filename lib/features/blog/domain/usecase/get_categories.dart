import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The public category catalog, in one page.
class GetCategories implements UseCase<List<CategoryRef>, NoParams> {
  final CategoryRepository categoryRepository;
  const GetCategories(this.categoryRepository);

  @override
  Future<Either<Failure, List<CategoryRef>>> call(NoParams params) {
    return categoryRepository.listCategories();
  }
}
