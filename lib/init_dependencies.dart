import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/network/api_connection_checker.dart';
import 'package:belog/core/network/api_origin_report.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/resilient_nowave_session_store.dart';
import 'package:belog/core/nowave/secure_nowave_session_store.dart';
import 'package:belog/core/nowave/session_store_migration.dart';
import 'package:belog/core/nowave/sqlite_nowave_session_store.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/l10n/sqlite_locale_preference_store.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/theme/sqlite_theme_store.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/notion_export/notion_export_repository_impl.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/data/notion_import/notion_import_repository_impl.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/repositories/account_security_repository_impl.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/auth/data/repositories/password_recovery_repository_impl.dart';
import 'package:belog/features/auth/domain/auth_intent_gate.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/repository/password_recovery_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/request_password_reset.dart';
import 'package:belog/features/auth/domain/usecases/reset_password.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/category_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/datasources/sqlite_draft_store.dart';
import 'package:belog/features/blog/data/datasources/sqlite_structured_body_recovery_store.dart';
import 'package:belog/features/blog/data/datasources/nowave_structured_edition_reader.dart';
import 'package:belog/features/blog/data/datasources/sqlite_publish_queue_store.dart';
import 'package:belog/features/blog/data/datasources/sqlite_reading_history_store.dart';
import 'package:belog/features/blog/data/publish/publish_queue_runner.dart';
import 'package:belog/features/blog/data/publish/publish_queue_service.dart';
import 'package:belog/features/blog/data/read_aloud/platform_speech_engine.dart';
import 'package:belog/features/blog/data/read_aloud/sqlite_read_aloud_preferences.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/data/repositories/category_repository_impl.dart';
import 'package:belog/features/blog/data/repositories/comment_repository_impl.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_category.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_author_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
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
import 'package:belog/features/blog/presentation/blocs/categories/categories_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/publish_queue/publish_queue_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/messages/data/repositories/message_repository_impl.dart';
import 'package:belog/features/messages/data/services/author_message_participant_names.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit_factory.dart';
import 'package:belog/features/messages/presentation/bloc/message_unread_badge_cubit.dart';
import 'package:belog/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_badge_cubit.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/data/datasources/author_relationship_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_search_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/account_session_repository_impl.dart';
import 'package:belog/features/user/data/repositories/author_relationship_repository_impl.dart';
import 'package:belog/features/user/data/repositories/author_repository_impl.dart';
import 'package:belog/features/user/data/repositories/author_search_repository_impl.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:belog/features/user/domain/repositories/account_session_repository.dart';
import 'package:belog/features/user/domain/repositories/author_relationship_repository.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/domain/usecases/browse_authors.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/domain/usecases/export_user_data.dart';
import 'package:belog/features/user/domain/usecases/get_author_relationships.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get_it/get_it.dart';
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

  // Say which backend this build targets before anything else can fail. The
  // origin is compiled in, so "it cannot connect" is usually answered by this
  // one line: a CI QA build carries `https://example.invalid`, and a
  // release/profile build cannot use a plain-HTTP origin at all. The same line
  // reaches the diagnostics report header (about page) for installed builds.
  AppLogger.debug(describeApiOrigin(uri, debugBuild: kDebugMode));

  final directory = await getApplicationDocumentsDirectory();
  final database = AppDatabase.open(File('${directory.path}/belog.sqlite'));
  // Isar is no longer supported (#107). A leftover `default.isar` is left in
  // place untouched; tell the log once so a developer knows why local drafts
  // from a pre-SQLite build did not show up.
  if (await database.takeRetiredIsarNotice(directory)) {
    AppLogger.debug(
      'found default.isar but the Isar importer was removed; '
      'local drafts from that build are not imported',
    );
  }

  // The no-wave session. Tokens live in the platform secure storage
  // (issue #46); the SQLite-backed store remains as the migration source
  // and the fallback when the secure store is unavailable. A small marker in
  // the SQLite metadata table says which of the two copies is current, so a
  // failed clear cannot resurrect an account and a broken keychain cannot
  // silently lose one (#102).
  final sessionStore = await openSessionStore(
    legacy: SqliteNowaveSessionStore(database),
    secure: const SecureNowaveSessionStore(),
    canary: const SecureNowaveSessionStore(
      key: SecureNowaveSessionStore.canaryKey,
    ),
    authority: SqliteSessionAuthorityStore(database),
  );
  final connectivity = ApiConnectionChecker(uri);
  final httpClient = http.Client();
  final sessionManager = NowaveSessionManager(
    client: NowaveApiClient(
      baseUrl: uri,
      httpClient: httpClient,
      connectivityEvidence: connectivity,
    ),
    store: sessionStore,
  );
  final apiClient = NowaveApiClient(
    baseUrl: uri,
    authenticator: sessionManager,
    httpClient: httpClient,
    connectivityEvidence: connectivity,
  );
  serviceLocator.registerSingleton<ConnectionChecker>(
    connectivity,
    dispose: (_) {
      connectivity.close();
      httpClient.close();
    },
  );
  await sessionManager.restore();

  serviceLocator.registerLazySingleton<NotionExportRepository>(
    () => NotionExportRepositoryImpl(apiClient),
  );
  serviceLocator.registerLazySingleton<NotionImportRepository>(
    () => NotionImportRepositoryImpl(apiClient),
  );
  _initAuth(sessionManager, apiClient, uri);
  await _initBlog(apiClient, sessionManager);
  _initComments(apiClient);
  _initAuthors(apiClient, uri);
  _initCategories(uri);
  _initUser(apiClient, sessionManager);

  serviceLocator.registerLazySingleton(() => database);
  serviceLocator.registerLazySingleton<BlogDraftStore>(
    () => SqliteBlogDraftStore(database, apiBaseUrl: uri),
  );
  serviceLocator.registerLazySingleton<StructuredBodyRecoveryStore>(
    () => SqliteStructuredBodyRecoveryStore(database, apiBaseUrl: uri),
  );
  serviceLocator.registerLazySingleton<StructuredRecoveryCatalog>(
    () => SqliteStructuredBodyRecoveryStore(database, apiBaseUrl: uri),
  );
  serviceLocator.registerFactory(
    () => ListStructuredRecoveries(
      catalog: serviceLocator<StructuredRecoveryCatalog>(),
      identity: sessionManager,
    ),
  );
  serviceLocator.registerLazySingleton<StructuredEditionReader>(
    () => NowaveStructuredEditionReader(apiClient),
  );
  serviceLocator.registerFactory(
    () => OpenStructuredEditingSession(
      reader: serviceLocator<StructuredEditionReader>(),
      store: serviceLocator<StructuredBodyRecoveryStore>(),
      identity: sessionManager,
    ),
  );
  // The publish queue (issue #23): what the server has not accepted yet.
  // Covers are copied into the app's own folder because a picker's temporary
  // file can be cleaned up while an entry waits for the network.
  serviceLocator.registerLazySingleton<PublishQueueStore>(
    () => SqlitePublishQueueStore(
      database,
      apiBaseUrl: uri,
      directory: Directory('${directory.path}/publish_queue'),
    ),
  );
  serviceLocator.registerLazySingleton(
    () => PublishQueueRunner(
      store: serviceLocator<PublishQueueStore>(),
      repository: serviceLocator<BlogRepository>(),
      identity: sessionManager,
      connectionChecker: serviceLocator<ConnectionChecker>(),
    ),
  );
  serviceLocator.registerLazySingleton(
    () => PublishQueueService(
      store: serviceLocator<PublishQueueStore>(),
      runner: serviceLocator<PublishQueueRunner>(),
      identity: sessionManager,
    ),
  );
  // The UI starts sends through the domain port, never through the data layer.
  serviceLocator.registerLazySingleton<PublishQueueDrainer>(
    () => serviceLocator<PublishQueueRunner>(),
  );
  serviceLocator.registerFactory(
    () => PublishQueueCubit(
      store: serviceLocator<PublishQueueStore>(),
      drainer: serviceLocator<PublishQueueDrainer>(),
      identity: sessionManager,
    ),
  );
  serviceLocator.registerLazySingleton(() => apiClient);
  serviceLocator.registerLazySingleton(() => sessionManager);

  // core
  serviceLocator.registerLazySingleton<ThemePreferenceStore>(
    () => SqliteThemePreferenceStore(serviceLocator<AppDatabase>()),
  );
  // Device-local reading history (issue #22); never synced anywhere.
  serviceLocator.registerLazySingleton<ReadingHistoryStore>(
    () => SqliteReadingHistoryStore(database),
  );
  serviceLocator.registerLazySingleton<ReadAloudPreferences>(
    () => SqliteReadAloudPreferences(database),
  );
  // One coordinator/channel for the whole app, shared by retained tab stacks.
  serviceLocator.registerLazySingleton(
    () => SpeechCoordinator(PlatformSpeechEngine()),
  );
  serviceLocator.registerLazySingleton(() => ThemeBloc(serviceLocator()));

  // Issue #108: the in-app language choice, persisted next to the theme.
  serviceLocator.registerLazySingleton<LocalePreferenceStore>(
    () => SqliteLocalePreferenceStore(serviceLocator<AppDatabase>()),
  );
  // The one content language every request and the offline cache read from;
  // the language bloc writes it before the interface rebuilds.
  serviceLocator.registerLazySingleton<ContentLocale>(() => ContentLocale());
  serviceLocator.registerLazySingleton(
    () => LocaleBloc(serviceLocator(), contentLocale: serviceLocator()),
  );

  serviceLocator.registerLazySingleton(() => AppUserCubit());
}

void _initAuth(
  NowaveSessionManager sessionManager,
  NowaveApiClient apiClient,
  Uri apiBaseUrl,
) {
  // One intent gate for the whole app: the data source fences session
  // adoption with it, and the bloc fences the UI and cache with the same ids.
  final intentGate = AuthIntentGate();
  // Datasource
  serviceLocator
    ..registerFactory<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(
        apiClient,
        sessionManager,
        intentGate: intentGate,
      ),
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
    // One guard across all password forms, even in retained tab stacks.
    ..registerLazySingleton<AccountSecurityRepository>(
      () => AccountSecurityRepositoryImpl(
        client: apiClient,
        session: sessionManager,
        connectionChecker: serviceLocator(),
        // A changed address has to survive a restart: the offline start path
        // reads it from the stored session.
        rememberEmail: sessionManager.updateEmail,
      ),
    )
    ..registerLazySingleton<PasswordRecoveryRepository>(
      () => PasswordRecoveryRepositoryImpl(
        client: apiClient,
        connectionChecker: serviceLocator(),
      ),
    )
    // Usecases
    ..registerFactory(() => RequestPasswordReset(serviceLocator()))
    ..registerFactory(() => ResetPassword(serviceLocator()))
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
        intentGate: intentGate,
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

Future<void> _initBlog(
  NowaveApiClient apiClient,
  NowaveSessionManager sessionManager,
) async {
  // Datasource
  serviceLocator
    ..registerFactory<BlogRemoteDataSource>(
      // `/me` routes are bound to the account that is active when they are
      // called, so an old page cannot read or write into a newer account.
      () => BlogRemoteDataSourceImpl(
        apiClient,
        identity: sessionManager,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
    )
    ..registerFactory<BlogLocalDataSource>(
      () => SqliteBlogCache(
        serviceLocator<AppDatabase>(),
        contentLocale: serviceLocator<ContentLocale>(),
      ),
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
    ..registerFactory(() => GetAuthorArticles(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetMyArticles(serviceLocator<BlogRepository>()))
    ..registerFactory(
      () => GetMyArticleEditions(serviceLocator<BlogRepository>()),
    )
    ..registerFactory(() => ResolveTag(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetArticlesByTag(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetDeletedBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(
      () => GetRelatedArticles(serviceLocator<BlogRepository>()),
    )
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
        sessionIdentity: sessionManager,
      ),
    )
    ..registerFactory(
      () => BlogByBloc(
        getAuthorArticles: serviceLocator<GetAuthorArticles>(),
        getMyArticles: serviceLocator<GetMyArticles>(),
        getMyArticleEditions: serviceLocator<GetMyArticleEditions>(),
      ),
    )
    ..registerFactory(
      () => TagArticlesBloc(
        resolveTag: serviceLocator<ResolveTag>(),
        getArticlesByTag: serviceLocator<GetArticlesByTag>(),
      ),
    )
    ..registerFactory(
      () => RecycleBinBloc(
        getDeletedBlogs: serviceLocator<GetDeletedBlogs>(),
        restoreDeletedBlog: serviceLocator<RestoreDeletedBlog>(),
        sessionIdentity: sessionManager,
      ),
    );
}

void _initComments(NowaveApiClient apiClient) {
  serviceLocator
    // Datasource
    ..registerFactory<CommentRemoteDataSource>(
      () => CommentRemoteDataSourceImpl(
        apiClient,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
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

/// Public category browsing. One app-lifetime client without an authenticator:
/// a category request never carries a reader's token, so a 401 cannot start a
/// refresh and an anonymous reader gets the same answer.
void _initCategories(Uri apiBaseUrl) {
  serviceLocator
    // Datasource
    ..registerLazySingleton<CategoryRemoteDataSource>(
      () => CategoryRemoteDataSourceImpl(
        baseUrl: apiBaseUrl,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<CategoryRepository>(
      () => CategoryRepositoryImpl(
        remote: serviceLocator<CategoryRemoteDataSource>(),
        connectionChecker: serviceLocator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => GetCategories(serviceLocator<CategoryRepository>()))
    ..registerFactory(() => GetCategory(serviceLocator<CategoryRepository>()))
    ..registerFactory(
      () => GetArticlesByCategory(serviceLocator<CategoryRepository>()),
    )
    // Cubit and bloc
    ..registerFactory(
      () => CategoriesCubit(getCategories: serviceLocator<GetCategories>()),
    )
    ..registerFactory(
      () => CategoryArticlesBloc(
        getCategory: serviceLocator<GetCategory>(),
        getArticlesByCategory: serviceLocator<GetArticlesByCategory>(),
      ),
    );
}

void _initAuthors(NowaveApiClient apiClient, Uri apiBaseUrl) {
  serviceLocator
    // Datasource
    ..registerFactory<AuthorRemoteDataSource>(
      () => AuthorRemoteDataSourceImpl(
        apiClient,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
    )
    // A single app-lifetime client without an authenticator for public lists.
    ..registerLazySingleton<AuthorRelationshipRemoteDataSource>(
      () => AuthorRelationshipRemoteDataSourceImpl(
        baseUrl: apiBaseUrl,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
    )
    // Search also uses an anonymous client and retains no result cache.
    ..registerLazySingleton<AuthorSearchRemoteDataSource>(
      () => AuthorSearchRemoteDataSourceImpl(
        baseUrl: apiBaseUrl,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<AuthorRepository>(
      () => AuthorRepositoryImpl(
        authorRemoteDataSource: serviceLocator<AuthorRemoteDataSource>(),
        connectionChecker: serviceLocator<ConnectionChecker>(),
      ),
    )
    ..registerFactory<AuthorRelationshipRepository>(
      () => AuthorRelationshipRepositoryImpl(
        remote: serviceLocator<AuthorRelationshipRemoteDataSource>(),
        connectionChecker: serviceLocator<ConnectionChecker>(),
      ),
    )
    ..registerFactory(
      () => GetAuthorRelationships(
        serviceLocator<AuthorRelationshipRepository>(),
      ),
    )
    ..registerFactory<AuthorSearchRepository>(
      () => AuthorSearchRepositoryImpl(
        remote: serviceLocator<AuthorSearchRemoteDataSource>(),
        connectionChecker: serviceLocator<ConnectionChecker>(),
      ),
    )
    ..registerFactory(
      () => SearchAuthors(serviceLocator<AuthorSearchRepository>()),
    )
    ..registerFactory(
      () => BrowseAuthors(serviceLocator<AuthorSearchRepository>()),
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
      () => UserRemoteDataSourceImpl(
        apiClient,
        sessionManager,
        contentLocale: serviceLocator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<UserRepository>(
      () => UserRepositoryImpl(
        serviceLocator<UserRemoteDataSource>(),
        serviceLocator<ConnectionChecker>(),
      ),
    )
    ..registerFactory<AccountSessionRepository>(
      () => AccountSessionRepositoryImpl(apiClient),
    )
    // The notification inbox (#23 follow-up): read on open, never polled.
    ..registerFactory<NotificationRepository>(
      () => NotificationRepositoryImpl(apiClient),
    )
    ..registerFactory(
      () => NotificationInboxCubit(
        repository: serviceLocator<NotificationRepository>(),
        identity: sessionManager,
      ),
    )
    // The profile menu badge: one number, read when the screen opens.
    ..registerFactory(
      () => NotificationBadgeCubit(
        repository: serviceLocator<NotificationRepository>(),
        identity: sessionManager,
      ),
    )
    // Private conversations (#198 follow-up): read on open, never polled.
    ..registerFactory<MessageRepository>(() => MessageRepositoryImpl(apiClient))
    ..registerFactory(
      () => MessageUnreadBadgeCubit(
        repository: serviceLocator<MessageRepository>(),
        identity: sessionManager,
      ),
    )
    // Conversation ids are the only identities the API sends, so names come
    // from the public author profile - bounded per screen, cached across
    // sessions because they are public data either way.
    ..registerLazySingleton<MessageParticipantNames>(
      () => AuthorMessageParticipantNames(serviceLocator<AuthorRepository>()),
    )
    ..registerFactory(
      () => MessageInboxCubit(
        repository: serviceLocator<MessageRepository>(),
        identity: sessionManager,
        names: serviceLocator<MessageParticipantNames>(),
      ),
    )
    // A conversation id comes from the route, so the container registers how
    // to build a thread rather than one thread.
    ..registerFactory(
      () => MessageThreadCubitFactory(
        repository: serviceLocator<MessageRepository>(),
        identity: sessionManager,
        names: serviceLocator<MessageParticipantNames>(),
      ),
    )
    // Usecases
    ..registerFactory(
      () => GetUserMediaLibraryPage(serviceLocator<UserRepository>()),
    )
    ..registerFactory(() => EditUserUseCase(serviceLocator<UserRepository>()))
    // Page-scoped blocs created and disposed with their routes.
    ..registerFactory(
      () => UserEditBloc(
        editUserUseCase: serviceLocator<EditUserUseCase>(),
        appUserCubit: serviceLocator(),
        sessionIdentity: sessionManager,
      ),
    )
    // Data export (issue #22): profile + own articles as a JSON file.
    ..registerLazySingleton<ExportUserData>(
      () => UserDataExporter(
        getBlogsByPoster: serviceLocator<GetBlogsByPoster>(),
      ),
    );
}
