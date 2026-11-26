import 'package:belog/core/storage/app_database.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/repositories/account_editorial_repository_impl.dart';
import 'package:belog/features/auth/data/repositories/account_security_repository_impl.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/auth/data/repositories/password_recovery_repository_impl.dart';
import 'package:belog/features/auth/domain/auth_intent_gate.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
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
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:get_it/get_it.dart';

/// Sign-up, sign-in, sign-out, password changes and recovery, and the
/// app-level listener that leaves the signed-in UI when a refresh fails.
void registerAuthModule(GetIt locator, DependencyContext context) {
  final apiClient = context.apiClient;
  final sessionManager = context.sessionManager;
  // One intent gate for the whole app: the data source fences session
  // adoption with it, and the bloc fences the UI and cache with the same ids.
  final intentGate = AuthIntentGate();
  // Datasource
  locator
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
        locator(),
        locator(),
        SqliteProfileCache(
          locator<AppDatabase>(),
          apiBaseUrl: context.apiBaseUrl,
        ),
        readingHistoryStore: locator<ReadingHistoryStore>(),
      ),
    )
    // One guard across all password forms, even in retained tab stacks.
    ..registerLazySingleton<AccountSecurityRepository>(
      () => AccountSecurityRepositoryImpl(
        client: apiClient,
        session: sessionManager,
        connectionChecker: locator(),
        // A changed address has to survive a restart: the offline start path
        // reads it from the stored session.
        rememberEmail: sessionManager.updateEmail,
      ),
    )
    ..registerLazySingleton<PasswordRecoveryRepository>(
      () => PasswordRecoveryRepositoryImpl(
        client: apiClient,
        connectionChecker: locator(),
      ),
    )
    // Whether this account may arrange the editorial structures. A factory,
    // not a singleton: the answer belongs to a session, and `EDITOR_USER_IDS`
    // or the role column can change underneath an open app.
    ..registerFactory<AccountEditorialRepository>(
      () => AccountEditorialRepositoryImpl(apiClient),
    )
    // Usecases
    ..registerFactory(() => RequestPasswordReset(locator()))
    ..registerFactory(() => ResetPassword(locator()))
    ..registerFactory(() => UserSignUp(locator()))
    ..registerFactory(() => UserLogin(locator()))
    ..registerFactory(() => UserSignOut(locator()))
    ..registerFactory(() => CurrentUser(locator()))
    // Bloc
    ..registerLazySingleton(
      () => AuthBloc(
        userSignUp: locator(),
        userLogin: locator(),
        userSignOut: locator(),
        currentUser: locator(),
        appUserCubit: locator(),
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
    // App-level auth service, started by the boot sequence once the session
    // is restored: drops the user out of the logged-in UI when a background
    // token refresh fails.
    ..registerLazySingleton(
      () => AuthSessionSync(
        statusStream: sessionManager.statusStream,
        currentSession: () => sessionManager.currentSession,
        currentUser: locator(),
        appUserCubit: locator(),
      ),
    );
}
