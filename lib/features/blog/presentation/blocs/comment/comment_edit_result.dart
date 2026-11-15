import 'package:belog/core/error/failures.dart';

/// Outcome of one manual edit attempt. An uncertain write is deliberately
/// different from a rejection: retrying after a timeout could overwrite a
/// change made by another device.
enum CommentEditStatus {
  saved,
  rejected,
  stale,
  sessionChanged,
  outcomeUnknown,
}

class CommentEditResult {
  const CommentEditResult(this.status, {this.failure});

  final CommentEditStatus status;
  final Failure? failure;
}
