import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';

/// Local body recovery, not an outbound publish queue. Implementations must
/// separate backend namespaces as well as every part of [StructuredBodyKey].
/// Unknown or corrupt rows must not be interpreted as absent or overwritten.
abstract interface class StructuredBodyRecoveryStore {
  Future<StructuredBodyRecovery?> load(StructuredBodyKey key);

  /// Create only when this key is absent. Return null on conflict, without
  /// replacing the other editor's work (even if it is invalid or unreadable).
  Future<StructuredBodyRecovery?> create({
    required StructuredBodyKey key,
    required StructuredArticleDraft base,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
    StructuredSessionMetadata? baseMetadata,
    StructuredSessionMetadata? sessionMetadata,
  });

  /// Replace only the exact locally loaded snapshot. A null result indicates a
  /// stale snapshot, a deleted/recreated row, or an externally altered row.
  /// The original base is immutable across updates.
  Future<StructuredBodyRecovery?> replace({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required DateTime updatedAt,
  });

  /// Save body and session metadata atomically against the complete previous
  /// snapshot. The original base and its metadata are never changed. A null
  /// result signals a local conflict, not permission to overwrite or publish.
  Future<StructuredBodyRecovery?> replaceSession({
    required StructuredBodyRecovery expected,
    required StructuredArticleDraft body,
    required StructuredSessionMetadata sessionMetadata,
    required DateTime updatedAt,
  });

  /// Delete only the exact locally loaded snapshot. A false result keeps any
  /// newer edit and does not rely on clocks or wall-clock ordering.
  Future<bool> discard(StructuredBodyRecovery expected);
}
