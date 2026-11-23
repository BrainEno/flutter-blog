import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/sqlite_comment_draft_store.dart';
import 'package:belog/features/blog/data/repositories/comment_repository_impl.dart';
import 'package:belog/features/blog/domain/repositories/comment_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:get_it/get_it.dart';

/// Article comments. `CommentBloc` is page-scoped and built by the viewer
/// route with the article's slug, like `BlogViewerCubit`, so it is not here.
void registerCommentsModule(GetIt locator, DependencyContext context) {
  locator
    // Datasource
    ..registerFactory<CommentRemoteDataSource>(
      () => CommentRemoteDataSourceImpl(
        context.apiClient,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<CommentRepository>(
      () => CommentRepositoryImpl(
        commentRemoteDataSource: locator<CommentRemoteDataSource>(),
        connectionChecker: locator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => GetComments(locator<CommentRepository>()))
    ..registerFactory(
      () => CreateComment(
        locator<CommentRepository>(),
        sessionIdentity: context.sessionManager,
      ),
    )
    ..registerFactory(() => DeleteComment(locator<CommentRepository>()))
    // Unsent comments, kept on this device per backend, account and article.
    // One instance, so every comment box shares its one queue of writes.
    ..registerLazySingleton<CommentDraftStore>(
      () => SqliteCommentDraftStore(
        locator<AppDatabase>(),
        apiBaseUrl: context.apiBaseUrl,
      ),
    );
}
