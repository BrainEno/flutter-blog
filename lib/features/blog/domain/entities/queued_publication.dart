/// A user-requested publication, not an ordinary auto-saved draft.
///
/// A queued or failed item is never an acknowledgement from the server.
/// Only [PublicationStatus.published] means the server confirmed the article.
enum PublicationStatus { queued, uploading, failed, published }

/// Persisted checkpoints around non-idempotent network operations.
enum PublicationPhase {
  ready,
  mediaSending,
  mediaReady,
  mediaUncertain,
  articleSending,
  complete,
}

class QueuedPublication {
  const QueuedPublication({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    required this.tags,
    required this.hasCover,
    required this.coverMime,
    required this.remoteCoverUrl,
    required this.possibleOrphan,
    required this.status,
    required this.phase,
    required this.requestJson,
    required this.attemptCount,
    required this.nextAttemptAt,
    required this.lastErrorCode,
    required this.publishedSlug,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerId;
  final String title;
  final String content;
  final List<String> tags;
  final bool hasCover;
  final String? coverMime;
  final String? remoteCoverUrl;

  /// Sticky after an ambiguous media upload, even if a later upload succeeds.
  final bool possibleOrphan;
  final PublicationStatus status;
  final PublicationPhase phase;

  /// Frozen article request, stored before the first article POST. It must
  /// not change while the result of that POST might be unknown.
  final String? requestJson;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? publishedSlug;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// A POST may have reached the server. Editing or removing the intent now
  /// would hide an uncertain publication or create a duplicate.
  bool get articleOutcomeUncertain =>
      phase == PublicationPhase.articleSending &&
      status != PublicationStatus.published;

  bool get canEdit =>
      status != PublicationStatus.uploading &&
      status != PublicationStatus.published &&
      !articleOutcomeUncertain;

  /// A prior upload may have left an unreferenced asset on the server. The
  /// current API provides no delete or automatic orphan-recovery endpoint.
  bool get mayHaveRemoteOrphan =>
      possibleOrphan ||
      phase == PublicationPhase.mediaUncertain ||
      (remoteCoverUrl != null && status != PublicationStatus.published);
}
