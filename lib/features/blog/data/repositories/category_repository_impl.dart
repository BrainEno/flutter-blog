import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/category_remote_data_source.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Public, online-only category reads. Nothing here is cached or written to
/// disk: the catalog is the server's, and a stale copy would outlive a rename.
class CategoryRepositoryImpl implements CategoryRepository {
  const CategoryRepositoryImpl({
    required this.remote,
    required this.connectionChecker,
  });

  final CategoryRemoteDataSource remote;
  final ConnectionChecker connectionChecker;

  @override
  Future<Either<Failure, List<CategoryRef>>> listCategories() async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(await remote.listCategories());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, CategoryRef?>> getCategory(String slug) async {
    final wanted = slug.trim();
    if (wanted.isEmpty) {
      return left(Failure.validation('分类标识无效'));
    }
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(await remote.getCategory(wanted));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, List<Blog>>> getArticlesByCategory(
    String slug, {
    required int offset,
  }) async {
    final wanted = slug.trim();
    if (wanted.isEmpty || offset < 0) {
      return left(Failure.validation('分类标识无效'));
    }
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      return right(
        await remote.getArticlesByCategory(wanted, offset: offset),
      );
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }
}
