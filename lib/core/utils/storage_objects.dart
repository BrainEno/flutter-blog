/// Single helper for Supabase Storage object paths and public URLs.
///
/// Both the blog-cover and avatar flows build their upload paths and parse
/// their delete paths here, so path/versioning/MIME rules stay consistent
/// and legacy objects (flat, extension-less paths) remain deletable.
library;

const String kBlogImagesBucket = 'blog_images';
const String kAvatarsBucket = 'avatars';

/// Marker segment of the public-object URL format:
/// `https://<project>.supabase.co/storage/v1/object/public/<bucket>/<path>`
const String _kPublicUrlMarker = '/object/public/';

/// Extracts the bucket-relative object path from a Storage public URL.
///
/// Accepts both legacy flat objects (path = blog/user id, no extension)
/// and current nested versioned paths, and ignores cache-busting query
/// parameters (`?v=...`). Returns `null` when [url] is not a public
/// object URL of that shape.
String? objectPathFromPublicUrl(String url) {
  final markerIndex = url.indexOf(_kPublicUrlMarker);
  if (markerIndex < 0) {
    return null;
  }
  var rest = url.substring(markerIndex + _kPublicUrlMarker.length);
  final queryIndex = rest.indexOf('?');
  if (queryIndex >= 0) {
    rest = rest.substring(0, queryIndex);
  }
  final fragmentIndex = rest.indexOf('#');
  if (fragmentIndex >= 0) {
    rest = rest.substring(0, fragmentIndex);
  }
  // The first segment is the bucket name; everything after it is the
  // object path inside that bucket.
  final bucketSeparator = rest.indexOf('/');
  if (bucketSeparator < 0) {
    return null;
  }
  final path = rest.substring(bucketSeparator + 1);
  return path.isEmpty ? null : path;
}

/// File extension (with leading dot) for an upload MIME type.
///
/// Unknown and missing types default to `.jpg`: the picker re-encodes to
/// JPEG when `imageQuality` is used.
String extensionForMime(String? mimeType) {
  return switch (mimeType) {
    'image/png' => '.png',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    'image/heic' || 'image/heif' => '.heic',
    _ => '.jpg',
  };
}

/// Object path for a blog cover: poster-scoped, blog-scoped and
/// versioned, so a re-upload never overwrites the object the current DB
/// row points at (the old object can be removed after the row flips).
String blogCoverObjectPath({
  required String posterId,
  required String blogId,
  required String version,
  required String extension,
}) {
  return 'covers/$posterId/$blogId/$version$extension';
}

/// Object path for an avatar upload: user-scoped and versioned.
String avatarObjectPath({
  required String userId,
  required String version,
  required String extension,
}) {
  return 'avatars/$userId/$version$extension';
}

/// Millisecond timestamp used as the version component of upload paths.
String storageVersionNow() => DateTime.now().millisecondsSinceEpoch.toString();
