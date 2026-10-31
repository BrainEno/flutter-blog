import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/network/api_connection_checker.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/secure_nowave_session_store.dart';
import 'package:belog/core/nowave/session_store_migration.dart';
import 'package:belog/core/nowave/sqlite_nowave_session_store.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/data/repositories/comment_repository_impl.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/author_repository_impl.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/domain/usecases/export_user_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:path_provider/path_provider.dart';

final serviceLocator = GetIt.instance;

Future<void> initDependencies() async {
  final apiBaseUrl = AppSecrets.apiBaseUrl;

  if (apiBaseUrl == null || apiBaseUrl.isEmpty) {
    throw StateError(
      'API base URL not configured. '
      'Set API_BASE_URL via --dart-define-from-file=env.json or --dart-define=API_BASE_URL=... '
      'See env.example.json for template.',
    );
  }

  // Validate URL format (scheme + authority, no query or fragment).
  final uri = Uri.tryParse(apiBaseUrl);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw StateError(
      'Invalid API_BASE_URL: "$apiBaseUrl". Must be a valid HTTP(S) origin '
      '(e.g., https://api.example.com) without a query or fragment.',
    );
  }

  final directory = await getApplicationDocumentsDirectory();
  final database = AppDatabase.open(File('${directory.path}/belog.sqlite'));
  try {
    await database.importLegacyIfNeeded(directory);
  } catch (_) {
    await database.close();
    rethrow;
  }

  // The no-wave session. Tokens live in the platform secure storage
  // (issue #46); the SQLite-backed store remains as the migration source
  // and the fallback when the secure store is unavailable.
  final sessionStore = await migrateSessionStoreToSecureStorage(
    legacy: SqliteNowaveSessionStore(database),
    secure: const SecureNowaveSessionStore(),
  );
  final sessionManager = NowaveSessionManager(
    client: NowaveApiClient(baseUrl: uri),
    store: sessionStore,
  );
  final apiClient = NowaveApiClient(
    baseUrl: uri,
    authenticator: sessionManager,
  );
  await sessionManager.restore();

  _initAuth(sessionManager, apiClient, uri);
  await _initBlog(apiClient);
  _initComments(apiClient);
  _initAuthors(apiClient);
  _initUser(apiClient, sessionManager);

  serviceLocator.registerLazySingleton(() => database);
  serviceLocator.registerLazySingleton<BlogDraftStore>(
    () => SqliteBlogDraftStore(database),
  );
  serviceLocator.registerLazySingleton(() => apiClient);
  serviceLocator.registerLazySingleton(() => sessionManager);

  serviceLocator.registerFactory(() => InternetConnection());
  // core
  serviceLocator.registerLazySingleton<ThemePreferenceStore>(
    () => SqliteThemePreferenceStore(serviceLocator<AppDatabase>()),
  );
  // Device-local reading history (issue #22); never synced anywhere.
  serviceLocator.registerLazySingleton<ReadingHistoryStore>(
    () => SqliteReadingHistoryStore(database),
  );
  serviceLocator.registerLazySingleton(() => ThemeBloc(serviceLocator()));

  serviceLocator.registerLazySingleton(() => AppUserCubit());
  // Opt in only for debug builds: development APIs can be reachable on a
  // LAN even when the public-internet probe cannot reach its endpoints.
  const useDevBackendProbe = bool.fromEnvironment('BELOG_DEV_BACKEND_CHECK');
  serviceLocator.registerFactory<ConnectionChecker>(
    () => kDebugMode && useDevBackendProbe
        ? ApiConnectionChecker(uri)
        : ConnectionCheckerImpl(serviceLocator()),
  );
}

void _initAuth(
  NowaveSessionManager sessionManager,
  NowaveApiClient apiClient,
  Uri apiBaseUrl,
) {
  // Datasource
  serviceLocator
    ..registerFactory<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(apiClient, sessionManager),
    )
    // Repository
    ..registerFactory<AuthRepository>(
      () => AuthRepositoryImpl(
        serviceLocator(),
        serviceLocator(),
        SqliteProfileCache(
          serviceLocator<AppDatabase>(),
          apiBaseUrl: apiBaseUrl,
        ),
        readingHistoryStore: serviceLocator<ReadingHistoryStore>(),
      ),
    )
    // Usecases
    ..registerFactory(() => UserSignUp(serviceLocator()))
    ..registerFactory(() => UserLogin(serviceLocator()))
    ..registerFactory(() => UserSignOut(serviceLocator()))
    ..registerFactory(() => CurrentUser(serviceLocator()))
    // Bloc
    ..registerLazySingleton(
      () => AuthBloc(
        userSignUp: serviceLocator(),
        userLogin: serviceLocator(),
        userSignOut: serviceLocator(),
        currentUser: serviceLocator(),
        appUserCubit: serviceLocator(),
        sessionGeneration: () => sessionManager.sessionGeneration,
        hasActiveSession: () => sessionManager.currentSession != null,
        isCurrentSessionUser: (user) {
          final session = sessionManager.currentSession;
          return session != null &&
              session.userId == user.id &&
              session.email == user.email;
        },
      ),
    )
    // App-level auth service, started in main() once the session is
    // restored: drops the user out of the logged-in UI when a background
    // token refresh fails.
    ..registerLazySingleton(
      () => AuthSessionSync(
        statusStream: sessionManager.statusStream,
        currentSession: () => sessionManager.currentSession,
        currentUser: serviceLocator(),
        appUserCubit: serviceLocator(),
      ),
    );
}

Future<void> _initBlog(NowaveApiClient apiClient) async {
  // Datasource
  serviceLocator
    ..registerFactory<BlogRemoteDataSource>(
      () => BlogRemoteDataSourceImpl(apiClient),
    )
    ..registerFactory<BlogLocalDataSource>(
      () => SqliteBlogCache(serviceLocator<AppDatabase>()),
    )
    // Repository
    ..registerFactory<BlogRepository>(
      () => BlogRepositoryImpl(
        serviceLocator<BlogRemoteDataSource>(),
        serviceLocator<BlogLocalDataSource>(),
        serviceLocator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => UploadBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetAllBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetBlogById(serviceLocator<BlogRepository>()))
    ..registerFactory(() => SearchBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(() => ToggleLikeBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => IsBlogLiked(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetUserLikedBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(() => UpdateBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => DeleteBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetBlogsByPoster(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetDeletedBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(
      () => RestoreDeletedBlog(serviceLocator<BlogRepository>()),
    )
    // Page-scoped blocs. Routes create one instance per page and dispose it
    // with the page, so request state never leaks across pages.
    ..registerFactory(
      () => BlogBloc(getAllBlogs: serviceLocator<GetAllBlogs>()),
    )
    ..registerFactory(
      () => BlogUploadBloc(
        uploadBlog: serviceLocator<UploadBlog>(),
        updateBlog: serviceLocator<UpdateBlog>(),
        deleteBlog: serviceLocator<DeleteBlog>(),
      ),
    )
    ..registerFactory(
      () => BlogSearchBloc(searchBlogs: serviceLocator<SearchBlogs>()),
    )
    ..registerFactory(
      () => BlogLikedBloc(
        toggleBlogLike: serviceLocator<ToggleLikeBlog>(),
        isBlogLiked: serviceLocator<IsBlogLiked>(),
        getUserLikedBlogs: serviceLocator<GetUserLikedBlogs>(),
      ),
    )
    ..registerFactory(
      () => BlogByBloc(getBlogsByPoster: serviceLocator<GetBlogsByPoster>()),
    )
    ..registerFactory(
      () => RecycleBinBloc(
        getDeletedBlogs: serviceLocator<GetDeletedBlogs>(),
        restoreDeletedBlog: serviceLocator<RestoreDeletedBlog>(),
      ),
    );
}

void _initComments(NowaveApiClient apiClient) {
  serviceLocator
    // Datasource
    ..registerFactory<CommentRemoteDataSource>(
      () => CommentRemoteDataSourceImpl(apiClient),
    )
    // Repository
    ..registerFactory<CommentRepository>(
      () => CommentRepositoryImpl(
        commentRemoteDataSource: serviceLocator<CommentRemoteDataSource>(),
        connectionChecker: serviceLocator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => GetComments(serviceLocator<CommentRepository>()))
    ..registerFactory(() => CreateComment(serviceLocator<CommentRepository>()))
    ..registerFactory(() => DeleteComment(serviceLocator<CommentRepository>()));
  // CommentBloc is page-scoped and built by the viewer route with the
  // article's slug, like BlogViewerCubit.
}

void _initAuthors(NowaveApiClient apiClient) {
  serviceLocator
    // Datasource
    ..registerFactory<AuthorRemoteDataSource>(
      () => AuthorRemoteDataSourceImpl(apiClient),
    )
    // Repository
    ..registerFactory<AuthorRepository>(
      () => AuthorRepositoryImpl(
        authorRemoteDataSource: serviceLocator<AuthorRemoteDataSource>(),
        connectionChecker: serviceLocator<ConnectionChecker>(),
      ),
    )
    // Usecases. AuthorCubit is page-scoped and built by the author route
    // with the profile's user id, like BlogViewerCubit.
    ..registerFactory(
      () => GetAuthorProfile(serviceLocator<AuthorRepository>()),
    )
    ..registerFactory(() => FollowAuthor(serviceLocator<AuthorRepository>()))
    ..registerFactory(() => UnfollowAuthor(serviceLocator<AuthorRepository>()));
}

void _initUser(NowaveApiClient apiClient, NowaveSessionManager sessionManager) {
  // Datasource
  serviceLocator
    ..registerFactory<UserRemoteDataSource>(
      () => UserRemoteDataSourceImpl(apiClient, sessionManager),
    )
    // Repository
    ..registerFactory<UserRepository>(
      () => UserRepositoryImpl(
        serviceLocator<UserRemoteDataSource>(),
        serviceLocator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => EditUserUseCase(serviceLocator<UserRepository>()))
    // Page-scoped blocs created and disposed with their routes.
    ..registerFactory(
      () => UserEditBloc(
        editUserUseCase: serviceLocator<EditUserUseCase>(),
        appUserCubit: serviceLocator(),
      ),
    )
    // Data export (issue #22): profile + own articles as a JSON file.
    ..registerLazySingleton<ExportUserData>(
      () => UserDataExporter(
        getBlogsByPoster: serviceLocator<GetBlogsByPoster>(),
      ),
    );
}
