import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/domain/repository/auth_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final ConnectionChecker connectionChecker;

  const AuthRepositoryImpl(this.remoteDataSource, this.connectionChecker);

  @override
  Future<Either<Failure, User>> currentUser() async {
    try {
      if (!await (connectionChecker.isConnected)) {
        final session = remoteDataSource.currentUserSession;

        if (session == null) {
          return left(Failure('请登录账户'));
        }

        return right(UserModel(
            id: session.user.id,
            email: session.user.email ?? '',
            name: '',
            updatedAt: DateTime.parse(session.user.updatedAt as String)));
      }
      final userModel = await remoteDataSource.getCurrentUserData();
      if (userModel == null) {
        return left(Failure("请登录账户"));
      }
      return right(userModel);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, User>> loginWithEmailPassword(
      {required String email, required String password}) async {
    // implement loginWithEmailPassword
    return _getUser(() async => await remoteDataSource.loginWithEmailPassword(
        email: email, password: password));
  }

  @override
  Future<Either<Failure, User>> signUpWithEmailPassword(
      {required String name,
      required String email,
      required String password}) async {
    //implement signUpWithEmailPassword
    return _getUser(() async => await remoteDataSource.signUpWithEmailPassword(
        name: name, email: email, password: password));
  }

  Future<Either<Failure, User>> _getUser(Future<User> Function() fn) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      final user = await fn();
      return right(user);
    } on sb.AuthException catch (e) {
      return left(Failure.auth(e.message, cause: e));
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
}
