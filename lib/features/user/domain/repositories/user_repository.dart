
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/common/entities/image_upload.dart';

abstract class UserRepository {
  /// Edits profile display data (name, bio, website, avatar).
  ///
  /// The e-mail address is not part of the editable profile: the backend
  /// offers no e-mail or password change endpoint yet (gap G2, see
  /// docs/supabase-to-nowave-migration.md), so those operations are not
  /// offered at all.
  ///
  /// [sessionFence] is the account that opened the form. Saving spans a
  /// profile read, an avatar upload and the profile write, so the fence is
  /// carried across all three: a form opened by account A must not write into
  /// account B after a switch (#104).
  Future<Either<Failure, User>> editUserInfo({
    required String userId,
    required String name,
    ImageUpload? avatar,
    required String bio,
    required String website,
    required NowaveSessionFence sessionFence,
  });
}
