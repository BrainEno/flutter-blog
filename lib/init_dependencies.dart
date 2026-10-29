import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/sqlite_blog_cache.dart';
import 'package:belog/core/storage/sqlite_draft_store.dart';
import 'package:belog/core/storage/sqlite_theme_store.dart';
import 'package:belog/core/utils/global_snackbar.dart';
import 'package:belog/features/blog/data/datasources/blog_draft_store.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/features/auth/auth_link_handler.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/data/auth_callback_resolver.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/resend_confirmation_email.dart';
import 'package:belog/features/auth/domain/usecases/send_password_reset_email.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/bog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/user/bloc/edit_account_bloc.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart'; // Ensure the correct UserRepository is imported
import 'package:belog/features/user/domain/usecases/change_email_usecase.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/domain/usecases/reset_password_usecase.dart';
import 'package:get_it/get_it.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final serviceLocator = GetIt.instance;

Future<void> initDependencies() async {
  final supabaseUrl = AppSecrets.supabaseUrl;
  final supabaseKey = AppSecrets.supabaseKey;

  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    throw StateError(
      'Supabase URL not configured. '
      'Set SUPABASE_URL via --dart-define-from-file=env.json or --dart-define=SUPABASE_URL=... '
      'See env.example.json for template.',
    );
  }
  if (supabaseKey == null || supabaseKey.isEmpty) {
    throw StateError(
      'Supabase key not configured. '
      'Set SUPABASE_KEY via --dart-define-from-file=env.json or --dart-define=SUPABASE_KEY=... '
      'See env.example.json for template.',
    );
  }

  // Validate URL format
  final uri = Uri.tryParse(supabaseUrl);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    throw StateError(
      'Invalid SUPABASE_URL: "$supabaseUrl". Must be a valid HTTPS URL (e.g., https://your-project.supabase.co)',
    );
  }

  _initAuth();
  await _initBlog();
  await _initUser();

  String sanitizeUserAgent(String input) {
    // Remove non-ASCII characters
    return input.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
  }

  // Example usage
  final osInfo = sanitizeUserAgent('Windows 10 家庭中文版');
  final userAgent = 'belog-app/1.0 ($osInfo)';

  final supabase = await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
    headers: {'User-Agent': userAgent},
  );

  final directory = await getApplicationDocumentsDirectory();
  final database = AppDatabase.open(File('${directory.path}/belog.sqlite'));
  try {
    await database.importLegacyIfNeeded(directory);
  } catch (_) {
    await database.close();
    rethrow;
  }

  serviceLocator.registerLazySingleton(() => database);
  serviceLocator.registerLazySingleton<BlogDraftStore>(
    () => SqliteBlogDraftStore(database),
  );
  serviceLocator.registerLazySingleton(() => supabase.client);

  serviceLocator.registerFactory(() => InternetConnection());
  // core
  serviceLocator.registerLazySingleton<ThemePreferenceStore>(
    () => SqliteThemePreferenceStore(serviceLocator<AppDatabase>()),
  );
  serviceLocator.registerLazySingleton(() => ThemeBloc(serviceLocator()));

  serviceLocator.registerLazySingleton(() => AppUserCubit());
  serviceLocator.registerFactory<ConnectionChecker>(
    () => ConnectionCheckerImpl(serviceLocator()),
  );
}

void _initAuth() {
  // Datasource
  serviceLocator
    ..registerFactory<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(serviceLocator<SupabaseClient>()),
    )
    // Repository
    ..registerFactory<AuthRepository>(
      () => AuthRepositoryImpl(serviceLocator(), serviceLocator()),
    )
    // Usecases
    ..registerFactory(() => UserSignUp(serviceLocator()))
    ..registerFactory(() => UserLogin(serviceLocator()))
    ..registerFactory(() => UserSignOut(serviceLocator()))
    ..registerFactory(() => CurrentUser(serviceLocator()))
    ..registerFactory(() => ResendConfirmationEmail(serviceLocator()))
    ..registerFactory(() => SendPasswordResetEmail(serviceLocator()))
    // Bloc
    ..registerLazySingleton(
      () => AuthBloc(
        userSignUp: serviceLocator(),
        userLogin: serviceLocator(),
        userSignOut: serviceLocator(),
        currentUser: serviceLocator(),
        resendConfirmationEmail: serviceLocator(),
        sendPasswordResetEmail: serviceLocator(),
        appUserCubit: serviceLocator(),
      ),
    )
    // App-level auth services, started in main() once Supabase is up.
    ..registerLazySingleton(
      () => AuthSessionSync(
        authStateStream:
            serviceLocator<SupabaseClient>().auth.onAuthStateChange,
        currentSession: () =>
            serviceLocator<SupabaseClient>().auth.currentSession,
        currentUser: serviceLocator(),
        appUserCubit: serviceLocator(),
      ),
    )
    ..registerLazySingleton(
      () => AuthLinkHandler(
        links: AppLinksDeepLinkSource(AppLinks()),
        resolveCallbackUrl: (url) => resolveSupabaseAuthCallback(
          auth: serviceLocator<SupabaseClient>().auth,
          url: url,
        ),
        onResult: (result, message) => showGlobalSnackBar(message),
      ),
    );
}

Future<void> _initBlog() async {
  // Datasource
  serviceLocator
    ..registerFactory<BlogRemoteDataSource>(
      () => BlogRemoteDataSourceImpl(serviceLocator<SupabaseClient>()),
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
    );
}

Future<void> _initUser() async {
  // Datasource
  serviceLocator
    ..registerFactory<UserRemoteDataSource>(
      () => UserRemoteDataSourceImpl(serviceLocator<SupabaseClient>()),
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
    ..registerFactory(
      () => ChangeEmailUseCase(serviceLocator<UserRepository>()),
    )
    ..registerFactory(
      () => ResetPasswordUseCase(serviceLocator<UserRepository>()),
    )
    // Page-scoped blocs created and disposed with their routes.
    ..registerFactory(
      () => UserEditBloc(
        editUserUseCase: serviceLocator<EditUserUseCase>(),
        appUserCubit: serviceLocator(),
      ),
    )
    ..registerFactory(
      () => EditAccountBloc(
        changeEmailUseCase: serviceLocator<ChangeEmailUseCase>(),
        resetPasswordUseCase: serviceLocator<ResetPasswordUseCase>(),
      ),
    );
}
