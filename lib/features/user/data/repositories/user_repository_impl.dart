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
    String? avatarMimeType,
  }) async {
    if (!await (connectionChecker.isConnected)) {
      return left(Failure.networkOffline());
    }
    UserModel userToUpdate;
    String? newAvatarUrl;
    String oldAvatarUrl;
    try {
      userToUpdate = await remoteDataSource.getUserById(userId);
      oldAvatarUrl = userToUpdate.avatarUrl;

      if (avatar != null) {
        // Versioned path: the new avatar is a NEW object, so the profile
        // row can flip to it atomically; the old object is only removed
        // after the update succeeds.
        newAvatarUrl = await remoteDataSource.uploadAvatar(
          userId: userId,
          image: avatar,
          mimeType: avatarMimeType,
        );
        userToUpdate = userToUpdate.copyWith(avatarUrl: newAvatarUrl);
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
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('editUserInfo failed', error: e, stackTrace: stackTrace);
      return left(mapErrorToFailure(e));
    }

    try {
      final userUpdated = await remoteDataSource.editUserInfo(userToUpdate);
      if (newAvatarUrl != null &&
          oldAvatarUrl.isNotEmpty &&
          oldAvatarUrl != newAvatarUrl) {
        // The profile row now points at the new avatar: retire the old
        // object. Best-effort - a failure leaves a logged orphan.
        await _removeOldAvatarQuietly(oldAvatarUrl);
      }
      return right(userUpdated);
    } on ServerException catch (e) {
      // The profile update failed: roll back the freshly uploaded avatar
      // so it does not orphan next to the still-referenced old one.
      if (newAvatarUrl != null) {
        await _removeFreshAvatarQuietly(newAvatarUrl);
      }
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error('editUserInfo failed', error: e, stackTrace: stackTrace);
      if (newAvatarUrl != null) {
        await _removeFreshAvatarQuietly(newAvatarUrl);
      }
      return left(mapErrorToFailure(e));
    }
  }

  /// Best-effort removal of the superseded avatar; the profile row
  /// already points at the new one.
  Future<void> _removeOldAvatarQuietly(String publicUrl) async {
    try {
      await remoteDataSource.removeAvatar(publicUrl);
    } catch (e, stackTrace) {
      AppLogger.error(
        'orphan avatar left behind (avatar replaced): $publicUrl',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Best-effort rollback of a just-uploaded avatar whose profile update
  /// failed.
  Future<void> _removeFreshAvatarQuietly(String publicUrl) async {
    try {
      await remoteDataSource.removeAvatar(publicUrl);
    } catch (e, stackTrace) {
      AppLogger.error(
        'orphan avatar left behind (profile update failed): $publicUrl',
        error: e,
        stackTrace: stackTrace,
      );
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
