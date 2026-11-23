import 'dart:convert';

import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/storage/backend_key.dart';
import 'package:belog/features/blog/domain/repositories/recent_search_store.dart';

/// [RecentSearchStore] in the app's `metadata` key/value table: one JSON
/// array per backend and account, so the feature needs no schema migration.
class SqliteRecentSearchStore implements RecentSearchStore {
  SqliteRecentSearchStore(this.database, {required Uri apiBaseUrl})
    : _backend = backendKeyOf(apiBaseUrl);

  final AppDatabase database;
  final String _backend;

  /// The metadata key of [userId]'s searches. JSON-encoded so neither part
  /// can run into the other, whatever characters they hold.
  String keyFor(String userId) =>
      'recent_searches:${jsonEncode([_backend, userId])}';

  @override
  Future<List<String>> load({required String userId}) async {
    final raw = await database.readMetadata(keyFor(userId));
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      // Rebuilt through the same rule a new search goes through, so a value
      // written by another version is trimmed, de-duplicated and capped.
      var queries = const <String>[];
      for (final entry in decoded.reversed) {
        if (entry is String) queries = rememberSearch(queries, entry);
      }
      return queries;
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save({required String userId, required List<String> queries}) {
    final key = keyFor(userId);
    if (queries.isEmpty) return database.deleteMetadata(key);
    return database.writeMetadata(
      key,
      jsonEncode(queries.take(AppLimits.recentSearches).toList()),
    );
  }
}
