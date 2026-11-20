import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/account_session_repository_impl.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:belog/features/user/domain/repositories/account_session_repository.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:belog/features/user/domain/usecases/export_user_data.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:get_it/get_it.dart';

/// The signed-in reader's own profile: editing, the media library, signed-in
/// devices and the data export.
void registerUserModule(GetIt locator, DependencyContext context) {
  final apiClient = context.apiClient;
  final sessionManager = context.sessionManager;
  // Datasource
  locator
    ..registerFactory<UserRemoteDataSource>(
      () => UserRemoteDataSourceImpl(
        apiClient,
        sessionManager,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<UserRepository>(
      () => UserRepositoryImpl(
        locator<UserRemoteDataSource>(),
        locator<ConnectionChecker>(),
      ),
    )
    ..registerFactory<AccountSessionRepository>(
      () => AccountSessionRepositoryImpl(apiClient),
    )
    // Usecases
    ..registerFactory(() => GetUserMediaLibraryPage(locator<UserRepository>()))
    ..registerFactory(() => EditUserUseCase(locator<UserRepository>()))
    // Page-scoped blocs created and disposed with their routes.
    ..registerFactory(
      () => UserEditBloc(
        editUserUseCase: locator<EditUserUseCase>(),
        appUserCubit: locator(),
        sessionIdentity: sessionManager,
      ),
    )
    // Data export (issue #22): profile + own articles as a JSON file.
    ..registerLazySingleton<ExportUserData>(
      () => UserDataExporter(getBlogsByPoster: locator<GetBlogsByPoster>()),
    );
}
