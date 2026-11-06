import 'package:belog/features/messages/domain/entities/message_participant.dart';

/// Resolves the user ids a conversation carries into public identities.
///
/// Names are decoration, never data: a conversation is complete without them,
/// so every failure here degrades to "we do not know who this is" instead of
/// failing the screen. Lookups are public reads (an author profile), so they
/// need no session fence and may be cached across accounts.
abstract interface class MessageParticipantNames {
  /// The participant behind [userId], or null when the server has no public
  /// profile for that account or the lookup failed.
  Future<MessageParticipant?> lookup(String userId);

  /// Everything already known about [ids], after resolving at most [limit] of
  /// the ids that are not cached yet. A few lookups run at a time, never all at
  /// once: an inbox of fifty conversations must not become fifty parallel
  /// requests.
  ///
  /// Only resolved identities are in the returned map; an id that could not be
  /// resolved is simply absent.
  Future<Map<String, MessageParticipant>> resolve(
    Iterable<String> ids, {
    int limit = defaultLookupBudget,
  });

  /// How many uncached lookups one [resolve] call may start.
  static const int defaultLookupBudget = 12;
}
