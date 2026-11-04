import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/datasources/article_payload.dart';

/// Reads and writes the viewer's like state for one article at a time.
///
/// The API sets an explicit like state rather than toggling, so a tap is a
/// read-then-write pair. Two overlapping pairs would both read the same
/// `current` and write the same new state, silently dropping one of the taps,
/// so toggles are serialized per article slug. Like state is the viewer's own,
/// so both halves name the account they belong to: a tap made for account A
/// must never land as B's like (#104).
class ArticleLikeStore {
  ArticleLikeStore({
    required NowaveApiClient client,
    required this.requireActiveFence,
    required this.identity,
  }) : _client = client;

  final NowaveApiClient _client;

  /// Reads the account a viewer-scoped call is made for, right now; throws
  /// when nobody is signed in.
  final NowaveSessionFence Function() requireActiveFence;

  /// Where the active account is read from. Null keeps the pre-fence
  /// behaviour for callers that never had an identity (older tests).
  final NowaveSessionIdentity? identity;

  /// One in-flight toggle per article, released on completion.
  final Map<String, Future<bool>> _toggleBySlug = {};

  /// Toggles the like for [userId] on [blogId], sharing the in-flight toggle
  /// so concurrent taps queue behind it instead of racing each other.
  Future<bool> toggle(String userId, String blogId) {
    // Share the in-flight toggle so concurrent callers queue behind it
    // instead of racing each other; the slot frees on completion.
    final inFlight = _toggleBySlug[blogId];
    if (inFlight != null) {
      return inFlight;
    }
    return _toggleBySlug[blogId] = _toggleLocked(userId, blogId).whenComplete(
      () {
        _toggleBySlug.remove(blogId);
      },
    );
  }

  Future<bool> _toggleLocked(String userId, String blogId) async {
    try {
      // The API sets an explicit like state rather than toggling, so the
      // current server state is read first and the opposite is written.
      // The response is the authoritative post-state. Like state is the
      // viewer's own, so both halves name the account they belong to: a tap
      // made for account A must never land as B's like (#104).
      final fence = _viewerFence(userId);
      final current = await _likedByViewer(blogId, fence);
      final data = fence == null
          ? await _client.putJson('/articles/$blogId/like', {'liked': !current})
          : await _client.putJson('/articles/$blogId/like', {
              'liked': !current,
            }, sessionFence: fence);
      final map = articlePayloadMap(data);
      return map['likedByViewer'] as bool? ?? !current;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  /// Reads the viewer's current like state without changing it.
  Future<bool> isLiked(String userId, String blogId) async {
    try {
      return await _likedByViewer(blogId, _viewerFence(userId));
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  /// The fence for an operation that names its viewer.
  ///
  /// Returns null when no identity was injected: those callers predate the
  /// fence and keep the old unfenced behaviour (see [identity]).
  NowaveSessionFence? _viewerFence(String userId) {
    if (identity == null) return null;
    final fence = requireActiveFence();
    if (userId.isNotEmpty && userId != fence.userId) {
      throw const NowaveApiException(
        statusCode: HttpStatus.conflict,
        code: 'SESSION_CHANGED',
        message: 'The like was started by a different account.',
      );
    }
    return fence;
  }

  Future<bool> _likedByViewer(String slug, [NowaveSessionFence? fence]) async {
    final data = fence == null
        ? await _client.getJson(
            '/articles/$slug/like',
            query: {'locale': 'zh-CN'},
          )
        : await _client.getJsonForViewer(
            '/articles/$slug/like',
            expectedUserId: fence.userId,
            query: {'locale': 'zh-CN'},
          );
    return articlePayloadMap(data)['likedByViewer'] as bool? ?? false;
  }

}
