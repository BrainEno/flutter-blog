import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:fpdart/fpdart.dart';

class EditUserUseCase implements UseCase<User, EditUserParams> {
  final UserRepository repository;

  const EditUserUseCase(this.repository);

  @override
  Future<Either<Failure, User>> call(EditUserParams params) async {
    return await repository.editUserInfo(
      userId: params.userId,
      name: params.name,
      avatar: params.avatar,
      avatarMimeType: params.avatarMimeType,
      website: params.website,
    );
  }
}

class EditUserParams {
  final String userId;
  final String name;
  final File? avatar;

  /// MIME type reported by the picker; uploaded as the object's
  /// contentType.
  final String? avatarMimeType;
  final String website;

  EditUserParams({
    required this.userId,
    required this.name,
    required this.website,
    this.avatar,
    this.avatarMimeType,
  });
}
