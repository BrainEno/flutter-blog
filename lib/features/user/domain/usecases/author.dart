import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetAuthorProfile implements UseCase<AuthorProfile, String> {
  final AuthorRepository authorRepository;
  const GetAuthorProfile(this.authorRepository);

  @override
  Future<Either<Failure, AuthorProfile>> call(String userId) {
    return authorRepository.getAuthorProfile(userId);
  }
}

class FollowAuthor implements UseCase<AuthorProfile, String> {
  final AuthorRepository authorRepository;
  const FollowAuthor(this.authorRepository);

  @override
  Future<Either<Failure, AuthorProfile>> call(String userId) {
    return authorRepository.followAuthor(userId);
  }
}

class UnfollowAuthor implements UseCase<AuthorProfile, String> {
  final AuthorRepository authorRepository;
  const UnfollowAuthor(this.authorRepository);

  @override
  Future<Either<Failure, AuthorProfile>> call(String userId) {
    return authorRepository.unfollowAuthor(userId);
  }
}
