import 'package:belog/core/nowave/nowave_session.dart';
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

  final FlutterSecureStorage _storage;

  const SecureNowaveSessionStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<NowaveSessionData?> read() async {
    final raw = await _storage.read(key: _kStorageKey);
    return NowaveSessionManager.decodeSession(raw);
  }

  @override
  Future<void> write(NowaveSessionData session) {
    return _storage.write(
      key: _kStorageKey,
      value: NowaveSessionManager.encodeSession(session),
    );
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _kStorageKey);
  }
}
