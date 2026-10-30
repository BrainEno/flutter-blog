import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/session_store_migration.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements NowaveSessionStore {
  NowaveSessionData? stored;
  int writes = 0;
  int clears = 0;
  Object Function()? readError;
  Object Function()? writeError;

  @override
  Future<NowaveSessionData?> read() async {
    final error = readError;
    if (error != null) throw error();
    return stored;
  }

  @override
  Future<void> write(NowaveSessionData session) async {
    final error = writeError;
    if (error != null) throw error();
    writes++;
    stored = session;
  }

  @override
  Future<void> clear() async {
    clears++;
    stored = null;
  }
}

NowaveSessionData _session() => NowaveSessionData(
  userId: 'u1',
  email: 'user@example.invalid',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

void main() {
  group('migrateSessionStoreToSecureStorage', () {
    test('moves a legacy session and returns the secure store', () async {
      final legacy = MemoryStore()..stored = _session();
      final secure = MemoryStore();

      final chosen = await migrateSessionStoreToSecureStorage(
        legacy: legacy,
        secure: secure,
      );

      expect(chosen, same(secure));
      expect(secure.stored?.refreshToken, 'refresh-1');
      expect(legacy.stored, isNull, reason: 'the legacy row must be deleted');
      expect(legacy.clears, 1);
    });

    test('a fresh install keeps the secure store untouched', () async {
      final legacy = MemoryStore();
      final secure = MemoryStore();

      final chosen = await migrateSessionStoreToSecureStorage(
        legacy: legacy,
        secure: secure,
      );

      expect(chosen, same(secure));
      expect(secure.writes, 0);
      expect(legacy.clears, 0);
    });

    test('a failing secure store falls back to the legacy store', () async {
      final legacy = MemoryStore()..stored = _session();
      final secure = MemoryStore()
        ..writeError = () => StateError('secure storage unavailable');

      final chosen = await migrateSessionStoreToSecureStorage(
        legacy: legacy,
        secure: secure,
      );

      expect(chosen, same(legacy));
      expect(legacy.stored, isNotNull, reason: 'the session must survive');
      expect(legacy.clears, 0, reason: 'the legacy row must not be deleted');
    });

    test('a failing legacy read falls back to the legacy store', () async {
      final legacy = MemoryStore()..readError = () => StateError('db locked');
      final secure = MemoryStore();

      final chosen = await migrateSessionStoreToSecureStorage(
        legacy: legacy,
        secure: secure,
      );

      expect(chosen, same(legacy));
    });
  });
}
