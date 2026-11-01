import 'dart:convert';
import 'dart:math' as math;

import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';

/// The server rejected or did not honor a cursor. A first continuation may
/// fall back to offset; a later one must stop rather than mix strategies.
class LatestFeedCursorUnavailable implements Exception {
  const LatestFeedCursorUnavailable();
}

/// More same-millisecond rows exist than the server's bounded window can
/// safely walk. This is not an empty/end-of-feed result.
class LatestFeedCursorTooDense implements Exception {
  const LatestFeedCursorTooDense();
}

class LatestFeedSlice {
  const LatestFeedSlice({required this.blogs, required this.nextCursor});

  final List<BlogModel> blogs;
  final String? nextCursor;
}

/// A local-only continuation for the latest online feed.
///
/// no-wave exposes `publishedAt` at millisecond precision, while PostgreSQL
/// may store microseconds. Using the exposed value as an exclusive cursor can
/// skip the rest of that millisecond (no-wave #133). Query just before the
/// *next* millisecond instead, and discard IDs already seen in the boundary
/// millisecond. The API's limit is 100, so a dense boundary must fail visibly
/// rather than silently lose rows or pretend the feed has ended.
///
/// The serialized token is held only in the active feed state. It is not the
/// cursor sent to the server, persisted in SQLite, or shared across feeds.
class LatestFeedContinuation {
  LatestFeedContinuation._(this.publishedAt, Set<String> seenIds)
    : seenIds = Set.unmodifiable(seenIds);

  static const int _serverLimit = 100;
  static const int _maxTokenLength = 8192;
  static const String _minimumUuid = '00000000-0000-0000-0000-000000000000';
  static final RegExp _timestampShape = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );
  static final RegExp _uuidShape = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final String publishedAt;
  final Set<String> seenIds;

  /// Number of server rows needed to retain one page after overlap removal.
  int get requestLimit =>
      math.min(kBlogPageSize + seenIds.length, _serverLimit);

  String get token {
    final sortedIds = seenIds.toList()..sort();
    return jsonEncode({'v': 1, 'at': publishedAt, 'seen': sortedIds});
  }

  /// Strict upper bound excludes the next millisecond itself. no-wave accepts
  /// the all-zero UUID, so no UUID can compare less at the exact upper bound.
  String get apiCursor {
    final upper = _upperBound(publishedAt)!;
    return base64Url
        .encode(utf8.encode('$upper|$_minimumUuid'))
        .replaceAll('=', '');
  }

  /// Returns null when an older/invalid response lacks a safe ordering key.
  static LatestFeedContinuation? tryStart(List<BlogModel> blogs) {
    if (blogs.isEmpty || blogs.length > kBlogPageSize) return null;
    final keys = _keys(blogs);
    if (keys == null) return null;
    final boundary = keys.last.publishedAt;
    if (_upperBound(boundary) == null) return null;
    return LatestFeedContinuation._(
      boundary,
      keys
          .where((key) => key.publishedAt == boundary)
          .map((key) => key.id)
          .toSet(),
    );
  }

  /// Reject malformed, unbounded or future-version local tokens rather than
  /// sending arbitrary cursor data to the server.
  static LatestFeedContinuation? tryDecode(String token) {
    if (token.isEmpty || token.length > _maxTokenLength) return null;
    try {
      final decoded = jsonDecode(token);
      if (decoded is! Map || decoded['v'] != 1 || decoded['at'] is! String) {
        return null;
      }
      final boundary = decoded['at'] as String;
      final rawIds = decoded['seen'];
      if (_upperBound(boundary) == null ||
          rawIds is! List ||
          rawIds.isEmpty ||
          rawIds.length > _serverLimit) {
        return null;
      }
      final ids = <String>{};
      for (final raw in rawIds) {
        if (raw is! String || !_uuidShape.hasMatch(raw)) return null;
        if (!ids.add(raw.toLowerCase())) return null;
      }
      return LatestFeedContinuation._(boundary, ids);
    } on FormatException {
      return null;
    }
  }

  /// Validates the entire returned window before displaying any rows. An old
  /// server that ignored the cursor normally returns rows above this bound;
  /// the caller can then choose the legacy strategy on the first continuation.
  LatestFeedSlice advance(List<BlogModel> rows) {
    if (rows.length > requestLimit) throw const LatestFeedCursorUnavailable();
    final keys = _keys(rows);
    if (keys == null) throw const LatestFeedCursorUnavailable();
    final upper = _upperBound(publishedAt)!;
    for (final key in keys) {
      if (key.publishedAt.compareTo(upper) >= 0) {
        throw const LatestFeedCursorUnavailable();
      }
    }

    final fresh = <BlogModel>[];
    final freshKeys = <_ArticleKey>[];
    for (var i = 0; i < rows.length; i++) {
      final key = keys[i];
      if (key.publishedAt == publishedAt && seenIds.contains(key.id)) continue;
      fresh.add(rows[i]);
      freshKeys.add(key);
    }
    // At the API limit a window may contain only already-seen IDs while more
    // rows remain below it. Do not report an empty or shortened terminal page.
    if (fresh.length < kBlogPageSize && rows.length == requestLimit) {
      throw const LatestFeedCursorTooDense();
    }
    final count = math.min(fresh.length, kBlogPageSize);
    if (count == 0) return const LatestFeedSlice(blogs: [], nextCursor: null);
    final chosen = fresh.sublist(0, count);
    final chosenKeys = freshKeys.sublist(0, count);
    final nextBoundary = chosenKeys.last.publishedAt;
    if (_upperBound(nextBoundary) == null) {
      throw const LatestFeedCursorUnavailable();
    }
    final nextSeen = nextBoundary == publishedAt ? {...seenIds} : <String>{};
    for (final key in chosenKeys) {
      if (key.publishedAt == nextBoundary) nextSeen.add(key.id);
    }
    if (nextSeen.length > _serverLimit) {
      throw const LatestFeedCursorTooDense();
    }
    return LatestFeedSlice(
      blogs: chosen,
      nextCursor: LatestFeedContinuation._(nextBoundary, nextSeen).token,
    );
  }

  static String? _upperBound(String value) {
    if (!_timestampShape.hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
      return null;
    }
    final upper = parsed.add(const Duration(milliseconds: 1)).toIso8601String();
    return _timestampShape.hasMatch(upper) ? upper : null;
  }

  static List<_ArticleKey>? _keys(List<BlogModel> blogs) {
    final keys = <_ArticleKey>[];
    final ids = <String>{};
    final slugs = <String>{};
    String? previousTime;
    for (final blog in blogs) {
      final time = blog.publishedAt;
      if (time == null ||
          _upperBound(time) == null ||
          !_uuidShape.hasMatch(blog.articleId) ||
          blog.id.isEmpty) {
        return null;
      }
      final id = blog.articleId.toLowerCase();
      if (!ids.add(id) ||
          !slugs.add(blog.id) ||
          (previousTime != null && time.compareTo(previousTime) > 0)) {
        return null;
      }
      previousTime = time;
      keys.add(_ArticleKey(time, id));
    }
    return keys;
  }
}

class _ArticleKey {
  const _ArticleKey(this.publishedAt, this.id);

  final String publishedAt;
  final String id;
}
