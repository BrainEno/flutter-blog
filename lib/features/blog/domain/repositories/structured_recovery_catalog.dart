import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';

/// A lightweight local index entry. It contains no body, metadata, or remote
/// authorization claim. An invalid identity is visible but cannot be opened.
class StructuredRecoveryIndexEntry {
  const StructuredRecoveryIndexEntry({required this.rowId, required this.key});
  final int rowId;
  final StructuredBodyKey? key;
}

class StructuredRecoveryIndexPage {
  StructuredRecoveryIndexPage({
    required List<StructuredRecoveryIndexEntry> entries,
    required this.nextCursor,
  }) : entries = List.unmodifiable(entries);
  final List<StructuredRecoveryIndexEntry> entries;

  /// Opaque local row ID; not an article ID or a server version.
  final int? nextCursor;
}

/// Queries one account inside the implementation's fixed backend namespace.
/// It must never decode the body or mutate a row while listing.
abstract interface class StructuredRecoveryCatalog {
  Future<StructuredRecoveryIndexPage> page({
    required String userId,
    int? afterRowId,
  });
}
