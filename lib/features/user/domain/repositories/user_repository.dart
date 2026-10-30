import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

abstract class UserRepository {
  /// Edits profile display data (name, website, avatar).
  ///
  /// The e-mail address is not part of the editable profile: the backend
  /// offers no e-mail or password change endpoint yet (gap G2, see
  /// docs/supabase-to-nowave-migration.md), so those operations are not
  /// offered at all.
  Future<Either<Failure, User>> editUserInfo({
    required String userId,
    required String name,
    required File? avatar,
    String? avatarMimeType,
    required String website,
  });
}
