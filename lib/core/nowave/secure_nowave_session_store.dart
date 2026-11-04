import 'package:belog/core/nowave/session/session_data.dart';
import 'package:belog/core/nowave/session/session_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [NowaveSessionStore] backed by the platform secure storage: the iOS
/// Keychain, the Android Keystore-backed encrypted storage, and the
/// equivalent vaults on desktop platforms.
///
/// Session tokens are the only long-lived credential the app holds, so
/// they live here rather than in the plain SQLite database (issue #46).
/// The storage key matches the legacy SQLite metadata key on purpose:
/// same logical slot, different - safer - medium.
class SecureNowaveSessionStore implements NowaveSessionStore {
  static const _kStorageKey = 'nowave_session_v1';

  /// Key of the startup canary: a separate slot that exercises write, read and
  /// delete on the real medium without ever touching the session (#102).
  static const canaryKey = 'nowave_session_probe_v1';

  final FlutterSecureStorage _storage;
  final String _key;

  const SecureNowaveSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    String key = _kStorageKey,
  }) : _storage = storage,
       _key = key;

  @override
  Future<NowaveSessionData?> read() async {
    final raw = await _storage.read(key: _key);
    return decodeNowaveSession(raw);
  }

  @override
  Future<void> write(NowaveSessionData session) {
    return _storage.write(key: _key, value: encodeNowaveSession(session));
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _key);
  }
}
