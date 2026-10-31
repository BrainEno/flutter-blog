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

/// Persists a confirmed profile for one authenticated account. The caller
/// must supply the account ID; cached display data is never authorization.
abstract interface class ProfileCacheStore {
  Future<CachedProfile?> read({required String userId});
  Future<void> write({required String userId, required CachedProfile profile});
  Future<void> clear({required String userId});
}

/// Account- and backend-scoped rows in the existing SQLite `metadata` table.
///
/// The legacy `cached_profile_v1` row has no owner. It is deliberately left
/// untouched and is never returned or attributed to the current account.
class SqliteProfileCache implements ProfileCacheStore {
  SqliteProfileCache(this.database, {required Uri apiBaseUrl})
    : _backendScope = _normalizeBackend(apiBaseUrl);

  final AppDatabase database;
  final String _backendScope;

  static String _normalizeBackend(Uri uri) {
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '${uri.origin}$path';
  }

  String _keyFor(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError(
        'A non-empty user ID is required for the profile cache.',
      );
    }
    String encode(String value) => base64Url.encode(utf8.encode(value));
    return 'cached_profile_v2:${encode(_backendScope)}:${encode(userId)}';
  }

  @override
  Future<CachedProfile?> read({required String userId}) async {
    final raw = await database.readMetadata(_keyFor(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CachedProfile.fromJson(decoded);
    } on FormatException {
      // A malformed cache reads as "no cache"; the next successful fetch
      // can replace it without assigning it to a different account.
      return null;
    } on TypeError {
      // Valid JSON with the wrong field types is malformed too.
      return null;
    }
  }

  @override
  Future<void> write({
    required String userId,
    required CachedProfile profile,
  }) => database.writeMetadata(_keyFor(userId), jsonEncode(profile.toJson()));

  @override
  Future<void> clear({required String userId}) =>
      database.deleteMetadata(_keyFor(userId));
}
