import 'package:belog/core/config/app_limits.dart';

/// Where the search page keeps a reader's recent searches.
///
/// Searches are private, so they belong to one signed-in account on one
/// backend - the same scope as the reading history - and never leave the
/// device. The list is stored newest first and already capped; the store
/// only keeps it.
abstract interface class RecentSearchStore {
  /// The saved searches of [userId], newest first; empty when there are none
  /// or the saved value cannot be read.
  Future<List<String>> load({required String userId});

  /// Replaces the saved searches of [userId] with [queries].
  Future<void> save({required String userId, required List<String> queries});
}

/// The key [query] is told apart by: trimmed, and the same whatever its case,
/// so "Wall" and "wall" are one search.
String recentSearchKey(String query) => query.trim().toLowerCase();

/// [recent] after searching for [query]: the query on top, any earlier copy
/// of it gone, at most [limit] entries. A blank query changes nothing.
List<String> rememberSearch(
  List<String> recent,
  String query, {
  int limit = AppLimits.recentSearches,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return recent;
  final key = recentSearchKey(trimmed);
  return [
    trimmed,
    ...recent.where((entry) => recentSearchKey(entry) != key),
  ].take(limit).toList(growable: false);
}

/// [recent] without [query] (compared like [rememberSearch] compares).
List<String> forgetSearch(List<String> recent, String query) {
  final key = recentSearchKey(query);
  return recent
      .where((entry) => recentSearchKey(entry) != key)
      .toList(growable: false);
}
