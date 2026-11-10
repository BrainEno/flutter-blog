import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetUserMediaLibraryPage
    implements UseCase<UserMediaPage, GetUserMediaLibraryPageParams> {
  const GetUserMediaLibraryPage(this.repository);

  final UserRepository repository;

  @override
  Future<Either<Failure, UserMediaPage>> call(
    GetUserMediaLibraryPageParams params,
  ) {
    return repository.getMediaLibraryPage(
      sessionFence: params.sessionFence,
      cursor: params.cursor,
    );
  }
}

class GetUserMediaLibraryPageParams {
  const GetUserMediaLibraryPageParams({
    required this.sessionFence,
    this.cursor,
  });

  final NowaveSessionFence sessionFence;
  final String? cursor;
}
