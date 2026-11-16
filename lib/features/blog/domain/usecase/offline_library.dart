import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Reads the device-only public article cache for the active server and content
/// language. Unlike online article search, this use case intentionally does not
/// ask the connection checker to probe a backend.
class GetOfflineLibrary implements UseCase<OfflineLibrarySnapshot, NoParams> {
  const GetOfflineLibrary(this._repository);

  final BlogRepository _repository;

  @override
  Future<Either<Failure, OfflineLibrarySnapshot>> call(NoParams params) =>
      _repository.getOfflineLibrary();
}

/// Removes only the current namespace of the public article cache after the UI
/// has obtained explicit confirmation. The repository keeps drafts, queues,
/// reading history and every other backend/locale out of this operation.
class ClearOfflineLibrary implements UseCase<void, NoParams> {
  const ClearOfflineLibrary(this._repository);

  final BlogRepository _repository;

  @override
  Future<Either<Failure, void>> call(NoParams params) =>
      _repository.clearOfflineLibrary();
}
