import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Resolves a stored tag name (as written on an article) to the taxonomy the
/// tag routes address. Null means "no such tag", not "no articles".
class ResolveTag implements UseCase<TagRef?, ResolveTagParams> {
  final BlogRepository blogRepository;
  const ResolveTag(this.blogRepository);

  @override
  Future<Either<Failure, TagRef?>> call(ResolveTagParams params) {
    return blogRepository.resolveTag(params.name);
  }
}

class ResolveTagParams {
  final String name;

  ResolveTagParams({required this.name});
}
