import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/user/data/datasources/author_relationship_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_search_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/author_relationship_repository_impl.dart';
import 'package:belog/features/user/data/repositories/author_repository_impl.dart';
import 'package:belog/features/user/data/repositories/author_search_repository_impl.dart';
import 'package:belog/features/user/domain/repositories/author_relationship_repository.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/domain/usecases/browse_authors.dart';
import 'package:belog/features/user/domain/usecases/get_author_relationships.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:get_it/get_it.dart';

/// Public author profiles, follow/unfollow, follower lists and the author
/// directory. `AuthorCubit` is page-scoped and built by the author route with
/// the profile's user id, like `BlogViewerCubit`, so it is not here.
void registerAuthorsModule(GetIt locator, DependencyContext context) {
  final apiBaseUrl = context.apiBaseUrl;
  locator
    // Datasource
    ..registerFactory<AuthorRemoteDataSource>(
      () => AuthorRemoteDataSourceImpl(
        context.apiClient,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // A single app-lifetime client without an authenticator for public lists.
    ..registerLazySingleton<AuthorRelationshipRemoteDataSource>(
      () => AuthorRelationshipRemoteDataSourceImpl(
        baseUrl: apiBaseUrl,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // Search also uses an anonymous client and retains no result cache.
    ..registerLazySingleton<AuthorSearchRemoteDataSource>(
      () => AuthorSearchRemoteDataSourceImpl(
        baseUrl: apiBaseUrl,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<AuthorRepository>(
      () => AuthorRepositoryImpl(
        authorRemoteDataSource: locator<AuthorRemoteDataSource>(),
        connectionChecker: locator<ConnectionChecker>(),
      ),
    )
    ..registerFactory<AuthorRelationshipRepository>(
      () => AuthorRelationshipRepositoryImpl(
        remote: locator<AuthorRelationshipRemoteDataSource>(),
        connectionChecker: locator<ConnectionChecker>(),
      ),
    )
    ..registerFactory(
      () => GetAuthorRelationships(locator<AuthorRelationshipRepository>()),
    )
    ..registerFactory<AuthorSearchRepository>(
      () => AuthorSearchRepositoryImpl(
        remote: locator<AuthorSearchRemoteDataSource>(),
        connectionChecker: locator<ConnectionChecker>(),
      ),
    )
    ..registerFactory(() => SearchAuthors(locator<AuthorSearchRepository>()))
    ..registerFactory(() => BrowseAuthors(locator<AuthorSearchRepository>()))
    // Usecases
    ..registerFactory(() => GetAuthorProfile(locator<AuthorRepository>()))
    ..registerFactory(() => FollowAuthor(locator<AuthorRepository>()))
    ..registerFactory(() => UnfollowAuthor(locator<AuthorRepository>()));
}
