import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
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
    required File? avatar,
    String? avatarMimeType,
    required String website,
  }) async {
    if (!await (connectionChecker.isConnected)) {
      return left(Failure.networkOffline());
    }
    try {
      final current = await remoteDataSource.getUserById(userId);
      var userToUpdate = current;

      if (avatar != null) {
        // Media assets are immutable: the new avatar is a NEW asset, the
        // profile row flips to it, and the old asset simply becomes
        // unreferenced (the backend keeps no delete endpoint; see gap G1
        // notes in docs/supabase-to-nowave-migration.md).
        final newAvatarUrl = await remoteDataSource.uploadAvatar(
          image: avatar,
          mimeType: avatarMimeType,
        );
        userToUpdate = userToUpdate.copyWith(avatarUrl: newAvatarUrl);
      }
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
    } catch (e) {
      return left(mapErrorToFailure(e));
    }
  }
}
