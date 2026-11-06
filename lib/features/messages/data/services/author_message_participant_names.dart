import 'dart:math' as math;

import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';

/// Resolves conversation participants through the public author profile.
///
/// The conversation endpoints only carry user ids, and there is no batch
/// profile endpoint, so this is one small public read per person. Three rules
/// keep that honest:
///
///   - **A failure is not a name.** Only a profile the server returned is
///     cached as an identity; a missing profile (404) is remembered as "no
///     such author" so a list does not re-ask, and a network failure is not
///     remembered at all, so the next visit tries again.
///   - **Bounded.** One [resolve] starts at most [lookupBudget] uncached
///     lookups, a few at a time. Pulling to refresh resolves the next batch.
///   - **Cached.** Identities are public data, so the cache outlives a session
///     switch and is capped instead of cleared.
class AuthorMessageParticipantNames implements MessageParticipantNames {
  AuthorMessageParticipantNames(
    this.authors, {
    this.lookupBudget = MessageParticipantNames.defaultLookupBudget,
    this.concurrency = 4,
  });

  /// How many identities the cache keeps before evicting the oldest.
  static const int cacheLimit = 200;

  final AuthorRepository authors;
  final int lookupBudget;
  final int concurrency;

  /// Insertion-ordered, so the first key is the oldest and eviction is cheap.
  final Map<String, MessageParticipant?> _cache = {};

  /// Ids the server answered with "no such author".
  static const String _notFoundCode = 'server.NOT_FOUND';

  @override
  Future<MessageParticipant?> lookup(String userId) async {
    if (userId.isEmpty) return null;
    if (_cache.containsKey(userId)) return _cache[userId];
    final result = await authors.getAuthorProfile(userId);
    return result.fold(
      (failure) {
        // A definite "no such author" is worth remembering; anything else
        // (offline, timeout, 5xx) is a temporary answer and must not become a
        // permanent "unknown person".
        if (failure.code == _notFoundCode) _remember(userId, null);
        return null;
      },
      (profile) {
        final participant = MessageParticipant(
          userId: userId,
          displayName: profile.displayName,
          avatarUrl: profile.avatarUrl,
        );
        _remember(userId, participant);
        return participant;
      },
    );
  }

  @override
  Future<Map<String, MessageParticipant>> resolve(
    Iterable<String> ids, {
    int limit = MessageParticipantNames.defaultLookupBudget,
  }) async {
    final distinct = <String>[];
    for (final id in ids) {
      if (id.isEmpty || distinct.contains(id)) continue;
      distinct.add(id);
    }
    final budget = limit < 0 ? 0 : limit;
    final pending = <String>[
      for (final id in distinct)
        if (!_cache.containsKey(id)) id,
    ].take(budget).toList();

    for (var start = 0; start < pending.length; start += concurrency) {
      final chunk = pending.sublist(
        start,
        math.min(start + concurrency, pending.length),
      );
      await Future.wait(chunk.map(lookup));
    }

    return {
      for (final id in distinct)
        if (_cache[id] != null) id: _cache[id]!,
    };
  }

  void _remember(String userId, MessageParticipant? participant) {
    _cache.remove(userId);
    _cache[userId] = participant;
    while (_cache.length > cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }
}
