import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';

/// [NowaveSessionStore] on the app's SQLite `metadata` table.
///
/// Legacy migration source and fallback when platform secure storage is
/// unavailable. Tokens are stored in the private SQLite database, not in
/// the platform keychain/keystore; see the audit for migration limitations.
class SqliteNowaveSessionStore implements NowaveSessionStore {
  static const _kMetadataKey = 'nowave_session_v1';

  final AppDatabase database;
  const SqliteNowaveSessionStore(this.database);

  @override
  Future<NowaveSessionData?> read() async {
    final raw = await database.readMetadata(_kMetadataKey);
    return NowaveSessionManager.decodeSession(raw);
  }

  @override
  Future<void> write(NowaveSessionData session) {
    return database.writeMetadata(
      _kMetadataKey,
      NowaveSessionManager.encodeSession(session),
    );
  }

  @override
  Future<void> clear() {
    return database.deleteMetadata(_kMetadataKey);
  }
}
