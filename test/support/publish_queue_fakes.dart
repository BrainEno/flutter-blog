import 'package:belog/core/common/entities/image_upload.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';

/// One queue row with the fields the UI cares about defaulted to a failed,
/// retryable entry.
PublishQueueEntry queueEntry({
  String id = 'queue-1',
  String userId = 'user',
  String title = '待发标题',
  String content = '待发正文',
  List<String> tags = const ['小说'],
  String idempotencyKey = 'key-1',
  PublishQueueStatus status = PublishQueueStatus.failed,
  int attempts = 3,
  String? lastErrorCode = 'network.offline',
  String? coverFileName,
  String? coverMimeType,
  String? coverUrl,
  PublishQueueKind kind = PublishQueueKind.create,
  String? targetId,
}) => PublishQueueEntry(
  id: id,
  userId: userId,
  title: title,
  content: content,
  tags: tags,
  idempotencyKey: idempotencyKey,
  status: status,
  attempts: attempts,
  createdAt: DateTime.utc(2026, 11, 5, 1),
  updatedAt: DateTime.utc(2026, 11, 5, 2),
  lastErrorCode: lastErrorCode,
  coverFileName: coverFileName,
  coverMimeType: coverMimeType,
  coverUrl: coverUrl,
  kind: kind,
  targetId: targetId,
);

/// A queue store that records calls instead of touching disk.
class FakePublishQueueStore implements PublishQueueStore {
  FakePublishQueueStore({
    List<PublishQueueEntry> rows = const [],
    this.storedCover,
  }) : rows = [...rows];

  List<PublishQueueEntry> rows;

  /// What [readCover] returns, whatever entry is asked for.
  ImageUpload? storedCover;

  /// URLs recorded by [recordCoverUrl], by entry id.
  final Map<String, String> coverUrls = {};

  final List<String> removed = [];
  final List<String> retried = [];
  final List<String> completed = [];
  final List<PublishQueueEntry> enqueued = [];
  int entriesCalls = 0;

  bool failRemove = false;

  @override
  Future<PublishQueueEntry> enqueue({
    required String userId,
    required String title,
    required String content,
    required List<String> tags,
    required String idempotencyKey,
    ImageUpload? cover,
    PublishQueueKind kind = PublishQueueKind.create,
    String? targetId,
  }) async {
    final entry = queueEntry(
      id: 'queued-${enqueued.length + 1}',
      userId: userId,
      title: title,
      content: content,
      tags: tags,
      idempotencyKey: idempotencyKey,
      status: PublishQueueStatus.queued,
      attempts: 0,
      lastErrorCode: null,
      kind: kind,
      targetId: targetId,
    );
    enqueued.add(entry);
    rows = [...rows, entry];
    return entry;
  }

  @override
  Future<List<PublishQueueEntry>> entries({required String userId}) async {
    entriesCalls++;
    return rows.where((row) => row.userId == userId).toList();
  }

  @override
  Future<PublishQueueEntry?> claimNext({
    required String userId,
    required DateTime now,
  }) async => null;

  @override
  Future<ImageUpload?> readCover(PublishQueueEntry entry) async => storedCover;

  @override
  Future<void> recordCoverUrl(String id, {required String url}) async {
    coverUrls[id] = url;
    final index = rows.indexWhere((row) => row.id == id);
    if (index >= 0) rows[index] = rows[index].copyWith(coverUrl: url);
  }

  @override
  Future<void> complete(String id) async => completed.add(id);

  @override
  Future<void> release(String id) async {}

  @override
  Future<void> recordFailure(
    String id, {
    required String errorCode,
    required bool retryable,
    DateTime? nextAttemptAt,
    bool countAttempt = true,
  }) async {}

  @override
  Future<void> remove(String id) async {
    if (failRemove) throw StateError('remove failed');
    removed.add(id);
    rows = rows.where((row) => row.id != id).toList();
  }

  @override
  Future<void> retry(String id) async => retried.add(id);

  @override
  Future<void> recoverInterrupted() async {}
}

/// A drainer that only counts how often the UI asked for a send.
class FakePublishQueueDrainer implements PublishQueueDrainer {
  int drains = 0;

  @override
  Future<int> drain() async {
    drains++;
    return 0;
  }
}
