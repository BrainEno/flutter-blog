import 'dart:convert';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';

/// Why metadata cannot be used without further inspection. The exact response
/// remains available in [StructuredEdition.rawArticle], including unknown keys.
enum StructuredMetadataIssue {
  missingSlug,
  missingTitle,
  missingSummary,
  missingWorkType,
  missingPublicationState,
  unknownPublicationState,
  missingTags,
  missingCategories,
  unknownArticleFields,
}

/// An exact server edition, read only for preparing a local editing session.
/// This is neither permission to publish nor a server-side version token.
class StructuredEdition {
  StructuredEdition({
    required this.key,
    required this.body,
    required this.metadata,
    required Map<String, dynamic> rawArticle,
    required Set<StructuredMetadataIssue> metadataIssues,
  }) : rawArticle = _freezeMap(jsonDecode(jsonEncode(rawArticle)) as Map),
       metadataIssues = Set.unmodifiable(metadataIssues);

  final StructuredBodyKey key;
  final StructuredArticleDraft body;
  final StructuredSessionMetadata metadata;
  final Map<String, Object?> rawArticle;
  final Set<StructuredMetadataIssue> metadataIssues;

  /// Detached copy for future inspection; never submit the read projection as
  /// a write body (it also contains server and viewer-owned fields).
  Map<String, dynamic> copyRawArticle() =>
      (jsonDecode(jsonEncode(rawArticle)) as Map<String, dynamic>);
}

Map<String, Object?> _freezeMap(Map value) => Map.unmodifiable({
  for (final entry in value.entries) entry.key as String: _freeze(entry.value),
});

Object? _freeze(Object? value) => switch (value) {
  Map map => _freezeMap(map),
  List list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};

/// The author's list has a hard limit and no offset. Absence from this window
/// says nothing about whether the article, edition, or server draft exists.
enum StructuredEditionReadStatus {
  found,
  notInAuthorWindow,
  editionMismatch,
  invalidResponse,
  unsupportedDocument,
  unavailable,
  authenticationRequired,
  sessionChanged,
}

class StructuredEditionReadResult {
  const StructuredEditionReadResult._(this.status, this.edition);
  const StructuredEditionReadResult.found(StructuredEdition value)
    : this._(StructuredEditionReadStatus.found, value);
  const StructuredEditionReadResult.failed(this.status)
    : assert(status != StructuredEditionReadStatus.found),
      edition = null;

  final StructuredEditionReadStatus status;
  final StructuredEdition? edition;
}
