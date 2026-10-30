import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';

/// The minimal profile shown while offline (issue #50): the last values
/// the server confirmed. Display-layer fallback only - it never takes
/// part in any authorization decision.
class CachedProfile {
  final String displayName;
  final String avatarUrl;
  final String website;
  final DateTime updatedAt;

  const CachedProfile({
    required this.displayName,
    required this.avatarUrl,
    required this.website,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'website': website,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static CachedProfile? fromJson(Map<String, dynamic> map) {
    final updatedAt = DateTime.tryParse(map['updatedAt'] as String? ?? '');
    if (updatedAt == null) return null;
    return CachedProfile(
      displayName: map['displayName'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String? ?? '',
      website: map['website'] as String? ?? '',
      updatedAt: updatedAt,
    );
  }
}

/// Persists the last successful profile fetch so an offline session
/// restore can still show a name and an avatar instead of a blank page.
abstract interface class ProfileCacheStore {
  Future<CachedProfile?> read();
  Future<void> write(CachedProfile profile);
  Future<void> clear();
}

/// [ProfileCacheStore] over the SQLite `metadata` table (a single JSON
/// row), so the cache shares the database's lifecycle and migrations.
class SqliteProfileCache implements ProfileCacheStore {
  static const _kKey = 'cached_profile_v1';

  final AppDatabase database;
  const SqliteProfileCache(this.database);

  @override
  Future<CachedProfile?> read() async {
    final raw = await database.readMetadata(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CachedProfile.fromJson(decoded);
    } on FormatException {
      // A corrupted cache reads as "no cache"; it is overwritten on the
      // next successful profile fetch.
      return null;
    }
  }

  @override
  Future<void> write(CachedProfile profile) => database.writeMetadata(
    _kKey,
    jsonEncode(profile.toJson()),
  );

  @override
  Future<void> clear() => database.deleteMetadata(_kKey);
}
