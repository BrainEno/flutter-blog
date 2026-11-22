import 'dart:typed_data';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';

/// How uploading a preview's local images ended.
sealed class NotionImageUploadOutcome {
  const NotionImageUploadOutcome();
}

/// Every image was uploaded or deliberately left out.
final class NotionImagesUploaded extends NotionImageUploadOutcome {
  const NotionImagesUploaded({required this.urls, required this.skipped});

  /// The media address for each uploaded image key.
  final Map<String, String> urls;

  /// File names of images that cannot be uploaded: unreadable, not an
  /// accepted type, or refused by the media service as invalid input.
  final List<String> skipped;
}

/// An upload failed for a reason other than the image itself - a lost
/// connection, a rate limit - and the rest were not tried.
final class NotionImageUploadStopped extends NotionImageUploadOutcome {
  const NotionImageUploadStopped(this.failure);
  final Failure failure;
}

/// The caller stopped wanting the result, e.g. the session changed.
final class NotionImageUploadAbandoned extends NotionImageUploadOutcome {
  const NotionImageUploadAbandoned();
}

/// Uploads a Notion export's local images to the author's media library,
/// one at a time, for one account.
///
/// Media uploads carry no idempotency key, so a failed upload is never
/// retried here; what was uploaded is remembered by content, so a second
/// preview - after a selection change, an expired plan or a failed upload -
/// uploads only the rest.
class NotionImageUploader {
  NotionImageUploader({required this.repository, required this.fence});

  final NotionImportRepository repository;
  final NowaveSessionFence fence;
  final Map<String, String> _uploaded = {};

  /// Forgets what was uploaded: the addresses belong to the account that
  /// uploaded them.
  void forget() => _uploaded.clear();

  /// Uploads the images [keys] name from [images]. [stillWanted] is asked
  /// after every network wait; [onProgress] after every image.
  Future<NotionImageUploadOutcome> upload(
    List<String> keys,
    Map<String, NotionLocalImage> images, {
    required bool Function() stillWanted,
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = <String, String>{};
    final skipped = <String>[];
    for (final (index, key) in keys.indexed) {
      final name = key.split('/').last;
      final bytes = _read(images[key]);
      final type = bytes == null ? null : notionUploadableImageType(bytes);
      if (bytes == null || type == null) {
        skipped.add(name);
      } else {
        final content = contentKey(name, bytes);
        var url = _uploaded[content];
        if (url == null) {
          final result = await repository.uploadImage(
            bytes: bytes,
            contentType: type,
            sessionFence: fence,
          );
          if (!stillWanted()) return const NotionImageUploadAbandoned();
          final failure = result.fold<Failure?>((f) => f, (_) => null);
          if (failure?.code == 'server.BAD_USER_INPUT') {
            // An animated or oversized image, say: the rest still go.
            skipped.add(name);
          } else if (failure != null) {
            return NotionImageUploadStopped(failure);
          } else {
            url = result.getOrElse((_) => '');
            _uploaded[content] = url;
          }
        }
        if (url != null) urls[key] = url;
      }
      onProgress?.call(index + 1, keys.length);
    }
    return NotionImagesUploaded(
      urls: Map.unmodifiable(urls),
      skipped: List.unmodifiable(skipped),
    );
  }

  static Uint8List? _read(NotionLocalImage? image) {
    if (image == null) return null;
    try {
      return image.read();
    } on NotionImportSourceException {
      return null;
    }
  }

  /// Name, size and a 32-bit FNV-1a hash of the bytes: enough to know an
  /// image already uploaded in this sheet, among at most a few dozen.
  static String contentKey(String name, Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return '$name:${bytes.length}:$hash';
  }
}
