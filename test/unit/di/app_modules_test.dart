import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/di/app_modules.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
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
import 'package:belog/features/blog/data/publish/publish_queue_runner.dart';
import 'package:belog/features/blog/data/publish/publish_queue_service.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/repositories/comment_repository.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_category.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/get_author_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:belog/features/blog/domain/usecase/offline_library.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:belog/features/blog/domain/views/article_view_recorder.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/categories/categories_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/offline_library/offline_library_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/publish_queue/publish_queue_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit_factory.dart';
import 'package:belog/features/messages/presentation/bloc/message_unread_badge_cubit.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_badge_cubit.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/data/datasources/author_relationship_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_search_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
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
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/source_files.dart';

/// The real container, built from the real modules (#304).
///
/// `service_locator_registration_test.dart` proves that every resolved type is
/// at least *named* in the wiring. This file goes further: it registers every
/// module from `lib/di/` on a fresh container - against an in-memory database
/// and an offline HTTP client - and resolves every registered type, so a
/// factory that asks for something nobody registered fails here instead of
/// as a red screen on the page that needs it.
///
/// The table below is checked against the modules' source in both
/// directions: a new registration without a row, or a row whose registration
/// was removed, fails the "table matches the modules" test.
const Map<String, _Row<Object>> _resolutions = {
  'AccountSecurityRepository': _Row<AccountSecurityRepository>(),
  'AccountSessionRepository': _Row<AccountSessionRepository>(),
  'AppDatabase': _Row<AppDatabase>(),
  'AppUserCubit': _Row<AppUserCubit>(),
  'AuthBloc': _Row<AuthBloc>(),
  'AuthRemoteDataSource': _Row<AuthRemoteDataSource>(),
  'AuthRepository': _Row<AuthRepository>(),
  'AuthSessionSync': _Row<AuthSessionSync>(),
  'AuthorRelationshipRemoteDataSource': (l) =>
      l<AuthorRelationshipRemoteDataSource>(),
  'AuthorRelationshipRepository': _Row<AuthorRelationshipRepository>(),
  'AuthorRemoteDataSource': _Row<AuthorRemoteDataSource>(),
  'AuthorRepository': _Row<AuthorRepository>(),
  'AuthorSearchRemoteDataSource': _Row<AuthorSearchRemoteDataSource>(),
  'AuthorSearchRepository': _Row<AuthorSearchRepository>(),
  'BlogBloc': _Row<BlogBloc>(),
  'BlogByBloc': _Row<BlogByBloc>(),
  'BlogDraftStore': _Row<BlogDraftStore>(),
  'BlogLikedBloc': _Row<BlogLikedBloc>(),
  'BlogLocalDataSource': _Row<BlogLocalDataSource>(),
  'BlogRemoteDataSource': _Row<BlogRemoteDataSource>(),
  'BlogRepository': _Row<BlogRepository>(),
  'BlogSearchBloc': _Row<BlogSearchBloc>(),
  'BlogUploadBloc': _Row<BlogUploadBloc>(),
  'BrowseAuthors': _Row<BrowseAuthors>(),
  'CategoriesCubit': _Row<CategoriesCubit>(),
  'CategoryArticlesBloc': _Row<CategoryArticlesBloc>(),
  'CategoryRemoteDataSource': _Row<CategoryRemoteDataSource>(),
  'CategoryRepository': _Row<CategoryRepository>(),
  'ClearOfflineLibrary': _Row<ClearOfflineLibrary>(),
  'CommentRemoteDataSource': _Row<CommentRemoteDataSource>(),
  'CommentRepository': _Row<CommentRepository>(),
  'ConnectionChecker': _Row<ConnectionChecker>(),
  'ContentLocale': _Row<ContentLocale>(),
  'CreateComment': _Row<CreateComment>(),
  'CurrentUser': _Row<CurrentUser>(),
  'DeleteBlog': _Row<DeleteBlog>(),
  'DeleteComment': _Row<DeleteComment>(),
  'EditUserUseCase': _Row<EditUserUseCase>(),
  'ExportUserData': _Row<ExportUserData>(),
  'FollowAuthor': _Row<FollowAuthor>(),
  'GetAllBlogs': _Row<GetAllBlogs>(),
  'GetArticlesByCategory': _Row<GetArticlesByCategory>(),
  'GetArticlesByTag': _Row<GetArticlesByTag>(),
  'GetAuthorArticles': _Row<GetAuthorArticles>(),
  'GetAuthorProfile': _Row<GetAuthorProfile>(),
  'GetAuthorRelationships': _Row<GetAuthorRelationships>(),
  'GetBlogById': _Row<GetBlogById>(),
  'GetBlogsByPoster': _Row<GetBlogsByPoster>(),
  'GetCategories': _Row<GetCategories>(),
  'GetCategory': _Row<GetCategory>(),
  'GetComments': _Row<GetComments>(),
  'GetDeletedBlogs': _Row<GetDeletedBlogs>(),
  'GetMyArticleEditions': _Row<GetMyArticleEditions>(),
  'GetMyArticles': _Row<GetMyArticles>(),
  'GetOfflineLibrary': _Row<GetOfflineLibrary>(),
  'GetRelatedArticles': _Row<GetRelatedArticles>(),
  'GetUserLikedBlogs': _Row<GetUserLikedBlogs>(),
  'GetUserMediaLibraryPage': _Row<GetUserMediaLibraryPage>(),
  'IsBlogLiked': _Row<IsBlogLiked>(),
  'ListStructuredRecoveries': _Row<ListStructuredRecoveries>(),
  'LocaleBloc': _Row<LocaleBloc>(),
  'LocalePreferenceStore': _Row<LocalePreferenceStore>(),
  'MessageInboxCubit': _Row<MessageInboxCubit>(),
  'MessageParticipantNames': _Row<MessageParticipantNames>(),
  'MessageRepository': _Row<MessageRepository>(),
  'MessageThreadCubitFactory': _Row<MessageThreadCubitFactory>(),
  'MessageUnreadBadgeCubit': _Row<MessageUnreadBadgeCubit>(),
  'NotificationBadgeCubit': _Row<NotificationBadgeCubit>(),
  'NotificationInboxCubit': _Row<NotificationInboxCubit>(),
  'NotificationRepository': _Row<NotificationRepository>(),
  'NotionExportRepository': _Row<NotionExportRepository>(),
  'NotionImportRepository': _Row<NotionImportRepository>(),
  'NowaveApiClient': _Row<NowaveApiClient>(),
  'NowaveSessionManager': _Row<NowaveSessionManager>(),
  'OfflineLibraryCubit': _Row<OfflineLibraryCubit>(),
  'OpenStructuredEditingSession': _Row<OpenStructuredEditingSession>(),
  'PasswordRecoveryRepository': _Row<PasswordRecoveryRepository>(),
  'PublishQueueCubit': _Row<PublishQueueCubit>(),
  'PublishQueueDrainer': _Row<PublishQueueDrainer>(),
  'PublishQueueRunner': _Row<PublishQueueRunner>(),
  'PublishQueueService': _Row<PublishQueueService>(),
  'PublishQueueStore': _Row<PublishQueueStore>(),
  'ReadAloudPreferences': _Row<ReadAloudPreferences>(),
  'ReadingHistoryStore': _Row<ReadingHistoryStore>(),
  'RecordArticleView': _Row<RecordArticleView>(),
  'RecycleBinBloc': _Row<RecycleBinBloc>(),
  'RequestPasswordReset': _Row<RequestPasswordReset>(),
  'ResetPassword': _Row<ResetPassword>(),
  'ResolveTag': _Row<ResolveTag>(),
  'RestoreDeletedBlog': _Row<RestoreDeletedBlog>(),
  'SearchAuthors': _Row<SearchAuthors>(),
  'SearchBlogs': _Row<SearchBlogs>(),
  'SpeechCoordinator': _Row<SpeechCoordinator>(),
  'StructuredBodyRecoveryStore': _Row<StructuredBodyRecoveryStore>(),
  'StructuredEditionReader': _Row<StructuredEditionReader>(),
  'StructuredRecoveryCatalog': _Row<StructuredRecoveryCatalog>(),
  'TagArticlesBloc': _Row<TagArticlesBloc>(),
  'ThemeBloc': _Row<ThemeBloc>(),
  'ThemePreferenceStore': _Row<ThemePreferenceStore>(),
  'ToggleLikeBlog': _Row<ToggleLikeBlog>(),
  'UnfollowAuthor': _Row<UnfollowAuthor>(),
  'UpdateBlog': _Row<UpdateBlog>(),
  'UploadBlog': _Row<UploadBlog>(),
  'UserEditBloc': _Row<UserEditBloc>(),
  'UserLogin': _Row<UserLogin>(),
  'UserRemoteDataSource': _Row<UserRemoteDataSource>(),
  'UserRepository': _Row<UserRepository>(),
  'UserSignOut': _Row<UserSignOut>(),
  'UserSignUp': _Row<UserSignUp>(),
};

/// One registered type: resolves it, or asks whether it is registered at all.
class _Row<T extends Object> {
  const _Row();

  T resolve(GetIt locator) => locator<T>();

  bool isRegisteredOn(GetIt locator) => locator.isRegistered<T>();
}

class _Offline implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => false;
}

class _MemoryStore implements NowaveSessionStore {
  NowaveSessionData? stored;

  @override
  Future<void> clear() async => stored = null;

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async => stored = session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory documents;
  late DependencyContext context;
  late List<GetIt> containers;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    documents = Directory.systemTemp.createTempSync('di_modules_test');
    final httpClient = MockClient((request) async => http.Response('{}', 503));
    final baseUrl = Uri.parse('https://api.example.invalid');
    final sessionManager = NowaveSessionManager(
      client: NowaveApiClient(baseUrl: baseUrl, httpClient: httpClient),
      store: _MemoryStore(),
    );
    context = DependencyContext(
      database: database,
      apiBaseUrl: baseUrl,
      apiClient: NowaveApiClient(
        baseUrl: baseUrl,
        authenticator: sessionManager,
        httpClient: httpClient,
      ),
      sessionManager: sessionManager,
      documentsDirectory: documents,
    );
    containers = [];
  });

  tearDown(() async {
    for (final locator in containers) {
      await locator.reset();
    }
    await database.close();
    documents.deleteSync(recursive: true);
  });

  /// A container wired the way `initDependencies` wires the app: the eager
  /// `ConnectionChecker` first, then the modules.
  GetIt build({List<DependencyModule> modules = appModules}) {
    final locator = GetIt.asNewInstance();
    containers.add(locator);
    locator.registerSingleton<ConnectionChecker>(_Offline());
    registerAppModules(locator, context, modules: modules);
    return locator;
  }

  /// Resolves every row of the table and returns what failed to resolve.
  /// Blocs and cubits are closed afterwards: some start loading as soon as
  /// they are built, and the database must outlive that work.
  Future<List<String>> resolveAll(GetIt locator) async {
    final failures = <String>[];
    final built = <Object>[];
    for (final entry in _resolutions.entries) {
      try {
        built.add(entry.value.resolve(locator));
      } catch (error) {
        failures.add('${entry.key}: $error');
      }
    }
    await pumpEventQueue(times: 50);
    for (final instance in built.whereType<BlocBase<Object?>>()) {
      await instance.close();
    }
    return failures;
  }

  test('every registered type resolves from the real modules', () async {
    final failures = await resolveAll(build());
    expect(
      failures,
      isEmpty,
      reason:
          'these registrations throw when resolved, so the page that needs '
          'them would fail at build time:\n${failures.join('\n')}',
    );
  });

  test('lazy singletons are shared and factories are not', () async {
    final locator = build();
    expect(identical(locator<AppDatabase>(), locator<AppDatabase>()), isTrue);
    expect(identical(locator<AppDatabase>(), database), isTrue);
    expect(
      identical(locator<NowaveSessionManager>(), context.sessionManager),
      isTrue,
    );
    // The UI starts sends through the domain port, which must be the very
    // runner the background service drives - not a second queue worker.
    expect(
      identical(locator<PublishQueueDrainer>(), locator<PublishQueueRunner>()),
      isTrue,
    );
    expect(
      identical(locator<BlogRepository>(), locator<BlogRepository>()),
      isFalse,
    );
    await resolveAll(locator);
  });

  test('module order does not matter: reversed modules resolve too', () async {
    final failures = await resolveAll(
      build(modules: appModules.reversed.toList()),
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('registering a module twice fails loudly instead of rewiring', () {
    final locator = build();
    expect(() => registerAppModules(locator, context), throwsA(isA<Error>()));
  });

  test('every module registers something and none overlap', () {
    final seen = <String, int>{};
    for (var index = 0; index < appModules.length; index++) {
      final locator = GetIt.asNewInstance();
      containers.add(locator);
      appModules[index](locator, context);
      for (final name in _resolutions.keys) {
        if (!_resolutions[name]!.isRegisteredOn(locator)) continue;
        expect(
          seen[name],
          isNull,
          reason: '$name is registered by more than one module',
        );
        seen[name] = index;
      }
      expect(
        seen.containsValue(index),
        isTrue,
        reason: 'module #$index registers nothing',
      );
    }
  });

  test('the table matches the modules in both directions', () {
    final registered = _registeredTypeNames();
    expect(registered.length, greaterThan(100));
    expect(
      registered.difference(_resolutions.keys.toSet()),
      isEmpty,
      reason: 'registered in lib/di but missing from the table',
    );
    expect(
      _resolutions.keys.toSet().difference(registered),
      isEmpty,
      reason: 'in the table but no longer registered by any module',
    );
  });
}

/// Every type the modules register, read from their source: the explicit
/// type argument when there is one, otherwise the constructed class.
Set<String> _registeredTypeNames() {
  const values = {
    'database': 'AppDatabase',
    'context.apiClient': 'NowaveApiClient',
    'context.sessionManager': 'NowaveSessionManager',
  };
  final registration = RegExp(
    r'register(?:Factory|LazySingleton|Singleton)(?:<(\w+)>)?\(\s*'
    r'(?://[^\n]*\n\s*)*\(\)\s*=>\s*(\w+(?:\.\w+)?)',
  );
  final names = <String>{'ConnectionChecker'};
  for (final file in dartFilesUnder('lib/di')) {
    for (final match in registration.allMatches(file.readAsStringSync())) {
      final value = match.group(2)!;
      names.add(match.group(1) ?? values[value] ?? value);
    }
  }
  return names;
}
