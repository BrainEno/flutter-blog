import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

/// Application-facing port for exporting a user's data and sharing the file.
/// The file system and platform share sheet are implementation details.
abstract interface class ExportUserData {
  Future<Either<Failure, void>> exportAndShare({
    required User user,
    required String shareTitle,
  });
}
