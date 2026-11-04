import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/datasources/article_payload.dart';

/// Turns tag names into server tag ids, with an in-memory cache and one
/// in-flight `POST /tags` per name.
///
/// Publishing several articles must not re-create the same tags, and two
/// concurrent publishes for the same name must share one request (the
/// create-or-reuse endpoint is idempotent, but halving the traffic is still
/// worth it). A failed resolution releases its slot immediately: it must not
/// poison the name for the rest of the app session.
class NowaveTagResolver {
  NowaveTagResolver(this._client);

  final NowaveApiClient _client;

  /// Tag name -> the server's tag object.
  final Map<String, Map<String, dynamic>> _byName = {};

  /// In-flight resolutions keyed by name and the account that asked, so a new
  /// login never joins the previous account's lookup.
  final Map<(String, int?, String?), Future<Map<String, dynamic>>> _lookups =
      {};

  /// Resolves tag names to tag ids via `POST /tags` (create-or-reuse), with
  /// an in-memory cache. Concurrent calls for the same name share one
  /// request (the create-or-reuse endpoint is idempotent, but halving the
  /// traffic is still worth it).
  Future<List<String>> resolveIds(
    List<String> tags,
    NowaveSessionFence? sessionFence,
  ) async {
    final names = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (names.isEmpty) return const <String>[];
    final ids = <String>[];
    for (final name in names) {
      final cached = _byName[name];
      if (cached != null) {
        ids.add(cached['id'] as String);
        continue;
      }
      final lookup = _claim(name, sessionFence);
      final tag = await lookup;
      _byName[name] = tag;
      ids.add(tag['id'] as String);
    }
    return ids;
  }

  /// Returns the in-flight (or freshly started) resolution for [name].
  ///
  /// The slot is released on success AND failure: a failed resolution
  /// must not poison the name for the rest of the app session, it just
  /// propagates its error to whoever joined it.
  Future<Map<String, dynamic>> _claim(
    String name,
    NowaveSessionFence? sessionFence,
  ) {
    // A new login must not join the previous account's in-flight lookup.
    final key = (name, sessionFence?.generation, sessionFence?.userId);
    final inFlight = _lookups[key];
    if (inFlight != null) {
      return inFlight;
    }
    return _lookups[key] = _resolve(name, sessionFence).whenComplete(() {
      _lookups.remove(key);
    });
  }

  Future<Map<String, dynamic>> _resolve(
    String name,
    NowaveSessionFence? sessionFence,
  ) async {
    final body = {'name': name};
    final data = sessionFence == null
        ? await _client.postJson('/tags', body)
        : await _client.postJson('/tags', body, sessionFence: sessionFence);
    return articlePayloadMap(data);
  }

}
