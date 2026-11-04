import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/common/entities/image_upload.dart';

class EditUserUseCase implements UseCase<User, EditUserParams> {
  final UserRepository repository;

  const EditUserUseCase(this.repository);

  @override
  Future<Either<Failure, User>> call(EditUserParams params) async {
    return await repository.editUserInfo(
      userId: params.userId,
      name: params.name,
      avatar: params.avatar,
      bio: params.bio,
      website: params.website,
      sessionFence: params.sessionFence,
    );
  }
}

class EditUserParams {
  final String userId;
  final String name;
  final ImageUpload? avatar;

  /// Public introduction; sent as-is so the backend never has to guess.
  final String bio;
  final String website;

  /// The account that opened the form (see `EditUserParams` callers): carried
  /// through the profile read, the avatar upload and the profile write so a
  /// switch in between cannot redirect the save into another account (#104).
  final NowaveSessionFence sessionFence;

  EditUserParams({
    required this.userId,
    required this.name,
    required this.bio,
    required this.website,
    required this.sessionFence,
    this.avatar,
  });
}
