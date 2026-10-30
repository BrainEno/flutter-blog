import 'package:belog/features/blog/domain/entities/blog.dart';

/// Public URL of a blog cover.
///
/// Cover media on the no-wave backend are immutable: every upload is a new
/// asset with its own id, so the URL itself changes whenever the cover is
/// replaced and no cache-busting suffix is needed.
String coverUrlOf(Blog blog) {
  return blog.imageUrl;
}
