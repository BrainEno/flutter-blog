import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';

/// [NowaveSessionStore] on the app's SQLite `metadata` table.
///
/// The tokens live in the app's private database directory, the same trust
/// domain as the offline blog cache. Swapping to a platform secure store
/// later only requires another implementation of [NowaveSessionStore].
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
