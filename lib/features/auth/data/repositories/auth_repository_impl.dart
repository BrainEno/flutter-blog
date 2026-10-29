import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/domain/entities/sign_up_outcome.dart';
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

        return right(
          UserModel(
            id: session.user.id,
            email: session.user.email ?? '',
            name: '',
            // `updatedAt` is nullable on the gotrue user; an offline
            // session restore must not crash on a missing value.
            updatedAt:
                _tryParseTimestamp(session.user.updatedAt) ?? DateTime.now(),
          ),
        );
      }
      final userModel = await remoteDataSource.getCurrentUserData();
      if (userModel == null) {
        // No session, or a session without a profile row. Either way the
        // user is not treated as logged in; profiles are owned by the
        // server-side trigger (see README "服务端（Supabase）待办").
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
    return _getUser(
      () async => await remoteDataSource.loginWithEmailPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<Either<Failure, SignUpOutcome>> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      final outcome = await remoteDataSource.signUpWithEmailPassword(
        name: name,
        email: email,
        password: password,
      );
      return right(outcome);
    } on sb.AuthException catch (e) {
      return left(Failure.auth(e.message, cause: e));
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }

  @override
  Future<Either<Failure, void>> resendConfirmationEmail(String email) async {
    return _runRemoteRequest(
      () async => await remoteDataSource.resendConfirmationEmail(email),
    );
  }

  @override
  Future<Either<Failure, void>> sendPasswordResetEmail(String email) async {
    return _runRemoteRequest(
      () async => await remoteDataSource.sendPasswordResetEmail(email),
    );
  }

  @override
  Future<Either<Failure, void>> logout() async {
    return _runRemoteRequest(() async => await remoteDataSource.logout());
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

  Future<Either<Failure, void>> _runRemoteRequest(
    Future<void> Function() fn,
  ) async {
    try {
      if (!await (connectionChecker.isConnected)) {
        return left(Failure('无法连接到网络'));
      }
      await fn();
      return right(null);
    } on ServerException catch (e) {
      return left(e.toFailure());
    }
  }
}

/// Parses a nullable ISO timestamp without throwing.
DateTime? _tryParseTimestamp(String? value) =>
    value == null ? null : DateTime.tryParse(value);
