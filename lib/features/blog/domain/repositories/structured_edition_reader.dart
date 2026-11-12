import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';

/// Authenticated read of one exact owner/article/locale. Never falls back to a
/// public article, a different account or a different content language.
abstract interface class StructuredEditionReader {
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  });
}
