import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/resilient_nowave_session_store.dart';
import 'package:belog/core/nowave/session_store_migration.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements NowaveSessionStore {
  NowaveSessionData? stored;
  int writes = 0;
  int clears = 0;
  Object Function()? readError;
  Object Function()? writeError;
  Object Function()? clearError;

  /// Lets a test make the medium silently wrong: the write "succeeds" but the
  /// value is not what the caller asked for.
  bool corruptWrites = false;

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
    stored = corruptWrites ? _session(refreshToken: 'garbage') : session;
  }

  @override
  Future<void> clear() async {
    final error = clearError;
    if (error != null) throw error();
    clears++;
    stored = null;
  }
}

class MemoryAuthority implements SessionAuthorityStore {
  String? marker;

  @override
  Future<String?> readMarker() async => marker;

  @override
  Future<void> writeMarker(String value) async => marker = value;
}

NowaveSessionData _session({String refreshToken = 'refresh-1'}) =>
    NowaveSessionData(
      userId: 'u1',
      email: 'user@example.invalid',
      accessToken: 'access-1',
      refreshToken: refreshToken,
      accessExpiresAt: DateTime.utc(2030),
      refreshExpiresAt: DateTime.utc(2030),
    );

void main() {
  group('openSessionStore', () {
    test('migrates a legacy session into secure storage', () async {
      final legacy = MemoryStore()..stored = _session();
      final secure = MemoryStore();
      final authority = MemoryAuthority();

      final store = await openSessionStore(
        legacy: legacy,
        secure: secure,
        canary: MemoryStore(),
        authority: authority,
      );

      expect(secure.stored?.refreshToken, 'refresh-1');
      expect(legacy.stored, isNull, reason: 'the legacy row must be deleted');
      expect(authority.marker, contains('"secure"'));
      expect((await store.read())?.refreshToken, 'refresh-1');
    });

    test('a fresh install keeps both media untouched', () async {
      final legacy = MemoryStore();
      final secure = MemoryStore();

      final store = await openSessionStore(
        legacy: legacy,
        secure: secure,
        canary: MemoryStore(),
        authority: MemoryAuthority(),
      );

      expect(secure.writes, 0);
      expect(legacy.clears, 0);
      expect(await store.read(), isNull);
    });

    test('a failing secure write keeps the session in SQLite', () async {
      final legacy = MemoryStore()..stored = _session();
      final secure = MemoryStore()
        ..writeError = () => StateError('secure storage unavailable');

      final store = await openSessionStore(
        legacy: legacy,
        secure: secure,
        canary: MemoryStore(),
        authority: MemoryAuthority(),
      );

      expect(legacy.stored, isNotNull, reason: 'the session must survive');
      expect(legacy.clears, 0, reason: 'the legacy row must not be deleted');
      expect((await store.read())?.refreshToken, 'refresh-1');
    });

    test('a copy that does not read back is never trusted', () async {
      final legacy = MemoryStore()..stored = _session();
      final secure = MemoryStore()..corruptWrites = true;
      final authority = MemoryAuthority();

      final store = await openSessionStore(
        legacy: legacy,
        secure: secure,
        canary: MemoryStore(),
        authority: authority,
      );

      expect(legacy.clears, 0, reason: 'unverified copy, legacy kept');
      expect(authority.marker, contains('"sqlite"'));
      expect((await store.read())?.refreshToken, 'refresh-1');
    });

    test('a failing legacy read still yields a usable store', () async {
      final legacy = MemoryStore()..readError = () => StateError('db locked');

      final store = await openSessionStore(
        legacy: legacy,
        secure: MemoryStore(),
        canary: MemoryStore(),
        authority: MemoryAuthority(),
      );

      expect(await store.read(), isNull);
    });

    test('an undeletable legacy row is disowned', () async {
      final legacy = MemoryStore()..stored = _session();
      legacy.clearError = () => StateError('db locked');
      final authority = MemoryAuthority();

      final store = await openSessionStore(
        legacy: legacy,
        secure: MemoryStore(),
        canary: MemoryStore(),
        authority: authority,
      );

      // The secure copy is verified and in charge; the leftover row is queued
      // for removal and never read as a second session.
      expect((await store.read())?.accessToken, 'access-1');
      expect(authority.marker, contains('"pendingRemoval"'));
    });
  });
}
