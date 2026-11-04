import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
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
    required String bio,
    required String website,
    required NowaveSessionFence sessionFence,
  }) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }
      // The fence is checked again after every step below: the form belongs
      // to the account that opened it, not to whoever is signed in now.
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
          sessionFence: sessionFence,
        );
        userToUpdate = userToUpdate.copyWith(avatarUrl: newAvatarUrl);
      }
      userToUpdate = userToUpdate.copyWith(
        id: userId,
        name: name,
        bio: bio,
        website: website.trim(),
        updatedAt: DateTime.now(),
      );

      final userUpdated = await remoteDataSource.editUserInfo(
        userToUpdate,
        sessionFence: sessionFence,
      );
      return right(userUpdated);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e) {
      return left(mapErrorToFailure(e));
    }
  }
}
