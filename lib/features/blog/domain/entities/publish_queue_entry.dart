/// Lifecycle of one queued publish (issue #23).
///
/// The queue records that the author *asked to publish*; a draft records that
/// the author typed something. They are different promises, so they live in
/// different places: a draft never leaves the device, a queued entry is an
/// intent to leave it.
enum PublishQueueStatus {
  /// Waiting for a session, a reachable backend, or the backoff window.
  queued,

  /// A send is in flight. Persisted on purpose: a crash mid-send must be
  /// visible on the next launch and replayed with the same idempotency key,
  /// not silently forgotten.
  uploading,

  /// Stopped until a human acts: the server rejected the content, or the retry
  /// budget ran out. A missing session does not land here - it only pauses the
  /// queue, because signing in again fixes it.
  failed,
}

/// One article waiting to be published from this device.
///
/// [idempotencyKey] is created once, when the entry is queued, and is sent as
/// the `Idempotency-Key` header on every attempt. The server replays the
/// article a retried request already created, so a lost response cannot turn
/// into a second article. It is never derived from the content: two identical
/// drafts by the same author are two intended pushes, not one.
class PublishQueueEntry {
  const PublishQueueEntry({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.tags,
    required this.idempotencyKey,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.coverFileName,
    this.coverMimeType,
    this.nextAttemptAt,
    this.lastErrorCode,
  });

  /// Local identifier (UUID). It is not a server identifier: nothing outside
  /// this device may ever treat it as an article address.
  final String id;

  /// The account that asked to publish. Only that account may send it.
  final String userId;

  final String title;
  final String content;
  final List<String> tags;

  /// Stable per queued intent; see the class doc.
  final String idempotencyKey;

  final PublishQueueStatus status;

  /// How many sends have been attempted. Reset by a manual retry.
  final int attempts;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cover stored inside the app's own directory, not the picker's temporary
  /// path: a queued entry may wait days and the picker copy would be gone.
  final String? coverFileName;
  final String? coverMimeType;

  /// When a retryable failure may be attempted again; null means "as soon as
  /// a session and a network are available".
  final DateTime? nextAttemptAt;

  /// Stable machine code of the last failure (`network.offline`, `auth.*`,
  /// `server.*`, ...). Never a raw exception message.
  final String? lastErrorCode;

  PublishQueueEntry copyWith({
    PublishQueueStatus? status,
    int? attempts,
    DateTime? updatedAt,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
  }) {
    return PublishQueueEntry(
      id: id,
      userId: userId,
      title: title,
      content: content,
      tags: tags,
      idempotencyKey: idempotencyKey,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      coverFileName: coverFileName,
      coverMimeType: coverMimeType,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
    );
  }
}
