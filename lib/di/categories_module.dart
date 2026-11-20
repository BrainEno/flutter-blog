import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/data/datasources/category_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/category_repository_impl.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_category.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/presentation/blocs/categories/categories_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:get_it/get_it.dart';

/// Public category browsing. One app-lifetime client without an authenticator:
/// a category request never carries a reader's token, so a 401 cannot start a
/// refresh and an anonymous reader gets the same answer.
void registerCategoriesModule(GetIt locator, DependencyContext context) {
  locator
    // Datasource
    ..registerLazySingleton<CategoryRemoteDataSource>(
      () => CategoryRemoteDataSourceImpl(
        baseUrl: context.apiBaseUrl,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<CategoryRepository>(
      () => CategoryRepositoryImpl(
        remote: locator<CategoryRemoteDataSource>(),
        connectionChecker: locator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => GetCategories(locator<CategoryRepository>()))
    ..registerFactory(() => GetCategory(locator<CategoryRepository>()))
    ..registerFactory(
      () => GetArticlesByCategory(locator<CategoryRepository>()),
    )
    // Cubit and bloc
    ..registerFactory(
      () => CategoriesCubit(getCategories: locator<GetCategories>()),
    )
    ..registerFactory(
      () => CategoryArticlesBloc(
        getCategory: locator<GetCategory>(),
        getArticlesByCategory: locator<GetArticlesByCategory>(),
      ),
    );
}
