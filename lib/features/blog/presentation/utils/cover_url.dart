import 'package:belog/features/blog/domain/entities/blog.dart';

/// Cache-busting public URL for a blog cover.
///
/// Shared by the feed card, the viewer page and the editor so every
/// surface re-fetches when a cover is re-uploaded (the object path is
/// versioned, so the URL itself changes too).
String coverUrlOf(Blog blog) {
  return blog.imageUrl.isEmpty
      ? ''
      : '${blog.imageUrl}?v=${blog.updatedAt.microsecondsSinceEpoch}';
}
