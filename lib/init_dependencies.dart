import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
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
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final serviceLocator = GetIt.instance;
late Isar isar;

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
      anonKey: supabaseKey,
      headers: {
        'User-Agent': userAgent,
      });

  final directory = await getApplicationDocumentsDirectory();
  isar = await Isar.open(
    [ThemePreferenceSchema, BlogSchema, BlogDraftSchema],
    directory: directory.path,
  );

  serviceLocator.registerLazySingleton(() => isar);
  serviceLocator.registerLazySingleton(() => supabase.client);

  serviceLocator.registerFactory(() => InternetConnection());
  // core
  serviceLocator.registerLazySingleton(() => ThemeBloc());

  serviceLocator.registerLazySingleton(() => AppUserCubit());
  serviceLocator.registerFactory<ConnectionChecker>(
      () => ConnectionCheckerImpl(serviceLocator()));
}

void _initAuth() {
  // Datasource
  serviceLocator
    ..registerFactory<AuthRemoteDataSource>(
        () => AuthRemoteDataSourceImpl(serviceLocator<SupabaseClient>()))
    // Repository
    ..registerFactory<AuthRepository>(
        () => AuthRepositoryImpl(serviceLocator(), serviceLocator()))
    // Usecases
    ..registerFactory(() => UserSignUp(serviceLocator()))
    ..registerFactory(() => UserLogin(serviceLocator()))
    ..registerFactory(() => UserSignOut(serviceLocator()))
    ..registerFactory(() => CurrentUser(serviceLocator()))
    // Bloc
    ..registerLazySingleton(() => AuthBloc(
          userSignUp: serviceLocator(),
          userLogin: serviceLocator(),
          userSignOut: serviceLocator(),
          currentUser: serviceLocator(),
          appUserCubit: serviceLocator(),
        ));
}

Future<void> _initBlog() async {
  // Datasource
  serviceLocator
    ..registerFactory<BlogRemoteDataSource>(
        () => BlogRemoteDataSourceImpl(serviceLocator<SupabaseClient>()))
    ..registerFactory<BlogLocalDataSource>(
        () => BlogLocalDataSourceImpl(isar: serviceLocator<Isar>()))
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
    ..registerFactory(() => SearchBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(() => ToggleLikeBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => IsBlogLiked(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetUserLikedBlogs(serviceLocator<BlogRepository>()))
    ..registerFactory(() => UpdateBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => DeleteBlog(serviceLocator<BlogRepository>()))
    ..registerFactory(() => GetBlogsByPoster(serviceLocator<BlogRepository>()))
    // Bloc
    ..registerLazySingleton(
        () => BlogBloc(getAllBlogs: serviceLocator<GetAllBlogs>()))
    ..registerLazySingleton(() => BlogUploadBloc(
        uploadBlog: serviceLocator<UploadBlog>(),
        updateBlog: serviceLocator<UpdateBlog>(),
        deleteBlog: serviceLocator<DeleteBlog>()))
    ..registerLazySingleton(
        () => BlogSearchBloc(searchBlogs: serviceLocator<SearchBlogs>()))
    ..registerLazySingleton(() => BlogLikedBloc(
        toggleBlogLike: serviceLocator<ToggleLikeBlog>(),
        isBlogLiked: serviceLocator<IsBlogLiked>(),
        getUserLikedBlogs: serviceLocator<GetUserLikedBlogs>()))
    ..registerLazySingleton(
        () => BlogByBloc(getBlogsByPoster: serviceLocator<GetBlogsByPoster>()));
}

Future<void> _initUser() async {
  // Datasource
  serviceLocator
    ..registerFactory<UserRemoteDataSource>(
        () => UserRemoteDataSourceImpl(serviceLocator<SupabaseClient>()))
    // Repository
    ..registerFactory<UserRepository>(() => UserRepositoryImpl(
        serviceLocator<UserRemoteDataSource>(),
        serviceLocator<ConnectionChecker>()))
    // Usecases
    ..registerFactory(() => EditUserUseCase(serviceLocator<UserRepository>()))
    ..registerFactory(
        () => ChangeEmailUseCase(serviceLocator<UserRepository>()))
    ..registerFactory(
        () => ResetPasswordUseCase(serviceLocator<UserRepository>()))
    //blocs
    ..registerLazySingleton(() => UserEditBloc(
          editUserUseCase: serviceLocator<EditUserUseCase>(),
          appUserCubit: serviceLocator(),
        ))
    ..registerLazySingleton(() => EditAccountBloc(
          changeEmailUseCase: serviceLocator<ChangeEmailUseCase>(),
          resetPasswordUseCase: serviceLocator<ResetPasswordUseCase>(),
        ));
}
