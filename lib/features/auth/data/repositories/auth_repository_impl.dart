import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:fpdart/fpdart.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final ConnectionChecker connectionChecker;

  const AuthRepositoryImpl(this.remoteDataSource, this.connectionChecker);

  @override
  Future<Either<Failure, User>> currentUser() async {
    try {
      if (!await (connectionChecker.isConnected)) {
        final session = remoteDataSource.currentSession;

        if (session == null) {
          return left(Failure('请登录账户'));
        }

        // Offline restore: the locally persisted session keeps the user
        // signed in with a minimal identity; the full profile is fetched
        // once the network is back.
        return right(
          UserModel(
            id: session.userId,
            email: session.email,
            name: '',
            updatedAt: DateTime.now(),
          ),
        );
      }
      final userModel = await remoteDataSource.getCurrentUserData();
      if (userModel == null) {
        // No session, or the session could not be refreshed. Either way
        // the user is not logged in.
        return left(Failure('登录状态已失效，请重新登录'));
      }
      return right(userModel);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, User>> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      final user = await remoteDataSource.loginWithEmailPassword(
        email: email,
        password: password,
      );
      return right(user);
    } on NowaveApiException catch (e) {
      return left(_loginFailure(e));
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, User>> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      // The backend signs the user in immediately: there is no e-mail
      // confirmation step.
      return right(
        await remoteDataSource.signUpWithEmailPassword(
          name: name,
          email: email,
          password: password,
        ),
      );
    } on NowaveApiException catch (e) {
      return left(_signUpFailure(e));
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      await remoteDataSource.logout();
      return right(null);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  /// Wrong credentials come back as a plain 401 UNAUTHENTICATED; the
  /// generic mapping would misleadingly say the login "expired".
  Failure _loginFailure(NowaveApiException e) {
    switch (e.code) {
      case 'UNAUTHENTICATED':
        return Failure.auth('邮箱或密码不正确', cause: e);
      case 'RATE_LIMITED':
        return Failure('尝试次数过多，请稍后再试', cause: e);
      case 'BAD_USER_INPUT':
        return Failure('邮箱或密码格式不正确', kind: FailureKind.validation, cause: e);
      default:
        return mapToServerException(e).toFailure();
    }
  }

  Failure _signUpFailure(NowaveApiException e) {
    switch (e.code) {
      case 'CONFLICT':
        return Failure('该邮箱已被注册，请直接登录', kind: FailureKind.validation, cause: e);
      case 'BAD_USER_INPUT':
        return Failure(
          '注册信息不符合要求，请检查邮箱与密码（密码至少 12 位）',
          kind: FailureKind.validation,
          cause: e,
        );
      case 'RATE_LIMITED':
        return Failure('注册过于频繁，请稍后再试', cause: e);
      default:
        return mapToServerException(e).toFailure();
    }
  }
}
