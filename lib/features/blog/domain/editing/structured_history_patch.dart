import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';

/// An all-or-nothing proposal to replace selected existing block contents
/// from one historical snapshot. Position, unselected blocks, document format
/// and metadata are never inferred or changed. Both inputs remain untouched.
/// This object is only a preview; the session independently checks the fence,
/// timeline generation and source entry again before admitting a local write.
final class StructuredHistoryPatch {
  StructuredHistoryPatch._({
    required this.current,
    required this.source,
    required this.blockIds,
    required this.result,
  });

  final StructuredArticleDraft current;
  final StructuredArticleDraft source;
  final Set<String> blockIds;
  final StructuredArticleDraft result;

  /// Creates a plan from exact immutable, validated snapshots. Each chosen ID
  /// must exist on both sides and actually differ in content. Restoring a block
  /// can change its type and any optional fields, but cannot change its ID or
  /// position. A bad selection or schema/size violation fails as a whole.
  factory StructuredHistoryPatch.prepare({
    required StructuredArticleDraft current,
    required StructuredArticleDraft source,
    required Set<String> blockIds,
  }) {
    if (blockIds.isEmpty || blockIds.length > 200) {
      throw const FormatException('Select one or more shared blocks');
    }
    final oldById = <String, Map<String, Object?>>{
      for (final block in current.blocks) block['id'] as String: block,
    };
    final historicalById = <String, Map<String, Object?>>{
      for (final block in source.blocks) block['id'] as String: block,
    };
    for (final id in blockIds) {
      final before = oldById[id];
      final historical = historicalById[id];
      if (before == null ||
          historical == null ||
          structuredComparisonJsonEquals(before, historical)) {
        throw const FormatException('Block is absent or unchanged');
      }
    }
    final merged = <Map<String, Object?>>[
      for (final block in current.blocks)
        blockIds.contains(block['id']) ? historicalById[block['id']]! : block,
    ];
    // Parse once after assembling the entire proposed document. Validation is
    // atomic: an oversize or incompatible mixed document is never installed.
    final result = StructuredArticleDraft.parse(
      version: current.version,
      blocks: merged,
    );
    return StructuredHistoryPatch._(
      current: current,
      source: source,
      blockIds: Set.unmodifiable(blockIds),
      result: result,
    );
  }
}
