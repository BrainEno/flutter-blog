import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

abstract class UserRepository {
  /// Edits profile display data (name, website, avatar).
  ///
  /// The e-mail address is deliberately NOT editable here: changing it
  /// must go through [changeEmail], i.e. Supabase Auth's update +
  /// confirmation flow, never a direct `profiles.email` write.
  Future<Either<Failure, User>> editUserInfo(
      {required String userId,
      required String name,
      required File? avatar,
      String? avatarMimeType,
      required String website});

  Future<Either<Failure, void>> changeEmail(String newEmail);
  Future<Either<Failure, void>> resetPassword(String newPassword);
}
