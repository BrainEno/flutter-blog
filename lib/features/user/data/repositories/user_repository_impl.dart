import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';

import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:fpdart/fpdart.dart';

class UserRepositoryImpl implements UserRepository {
  final UserRemoteDataSource remoteDataSource;
  final ConnectionChecker connectionChecker;

  const UserRepositoryImpl(this.remoteDataSource, this.connectionChecker);

  @override
  Future<Either<Failure, User>> editUserInfo({
    required String userId,
    required String name,
    required String website,
    required File? avatar,
  }) async {
    if (!await (connectionChecker.isConnected)) {
      return left(Failure.networkOffline());
    }
    try {
      UserModel userToUpdate = await remoteDataSource.getUserById(userId);

      if (avatar != null) {
        final imageUrl = await remoteDataSource.uploadAvatar(
          userId: userId,
          image: avatar,
        );
        userToUpdate = userToUpdate.copyWith(avatarUrl: imageUrl);
      }
      // The e-mail column is intentionally not written: the auth e-mail
      // only changes through Supabase Auth's confirmation flow
      // (changeEmail), never a direct profiles update.
      userToUpdate = userToUpdate.copyWith(
        id: userId,
        name: name,
        website: website,
        updatedAt: DateTime.now(),
      );

      final userUpdated = await remoteDataSource.editUserInfo(userToUpdate);
      return right(userUpdated);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('editUserInfo failed', error: e, stackTrace: stackTrace);
      return left(mapErrorToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> changeEmail(String newEmail) async {
    if (!await connectionChecker.isConnected) {
      return left(Failure.networkOffline());
    }
    try {
      await remoteDataSource.changeEmail(newEmail);
      return right(null);
    } catch (e, stackTrace) {
      AppLogger.error('changeEmail failed', error: e, stackTrace: stackTrace);
      return left(mapErrorToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword(String newPassword) async {
    if (!await connectionChecker.isConnected) {
      return left(Failure.networkOffline());
    }
    try {
      await remoteDataSource.changePassword(newPassword);
      return right(null);
    } catch (e, stackTrace) {
      AppLogger.error(
        'changePassword failed',
        error: e,
        stackTrace: stackTrace,
      );
      return left(mapErrorToFailure(e));
    }
  }
}
