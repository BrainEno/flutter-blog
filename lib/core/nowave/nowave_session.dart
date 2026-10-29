import 'dart:async';
import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/utils/app_logger.dart';

/// A persisted no-wave session: the rotated token pair plus the identity
/// the app caches locally (the backend's `GET /me` returns only an id, so
/// the e-mail address shown in the profile UI comes from what the user
/// typed at sign-in time).
class NowaveSessionData {
  const NowaveSessionData({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'email': email,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accessExpiresAt': accessExpiresAt.toIso8601String(),
    'refreshExpiresAt': refreshExpiresAt.toIso8601String(),
  };

  static NowaveSessionData fromJson(Map<String, dynamic> map) =>
      NowaveSessionData(
        userId: map['userId'] as String? ?? '',
        email: map['email'] as String? ?? '',
        accessToken: map['accessToken'] as String? ?? '',
        refreshToken: map['refreshToken'] as String? ?? '',
        accessExpiresAt:
            DateTime.tryParse(map['accessExpiresAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        refreshExpiresAt:
            DateTime.tryParse(map['refreshExpiresAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// The token pair returned by `POST /auth/{register,login,refresh}`.
class NowaveTokenPair {
  const NowaveTokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  static NowaveTokenPair fromDataMap(Map<String, dynamic> map) {
    DateTime parse(String key) =>
        DateTime.tryParse(map[key] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return NowaveTokenPair(
      accessToken: map['accessToken'] as String? ?? '',
      refreshToken: map['refreshToken'] as String? ?? '',
      accessExpiresAt: parse('accessExpiresAt'),
      refreshExpiresAt: parse('refreshExpiresAt'),
    );
  }
}

/// Auth status broadcast by [NowaveSessionManager].
sealed class NowaveAuthStatus {
  const NowaveAuthStatus();
}

final class NowaveAuthSignedIn extends NowaveAuthStatus {
  const NowaveAuthSignedIn(this.userId);

  final String userId;
}

final class NowaveAuthSignedOut extends NowaveAuthStatus {
  const NowaveAuthSignedOut();
}

/// Durable storage for the session. Implemented on top of the app's SQLite
/// `metadata` table (the same trust domain as the blog cache; the tokens
/// never leave the device). Swapping to a platform secure store later is a
/// drop-in replacement of this interface.
abstract class NowaveSessionStore {
  Future<NowaveSessionData?> read();
  Future<void> write(NowaveSessionData session);
  Future<void> clear();
}

/// Owns the no-wave session lifecycle: adopting token pairs from
/// login/register, rotating the refresh token, and broadcasting
/// sign-in/sign-out to the rest of the app (the replacement for
/// Supabase's `onAuthStateChange`).
///
/// The refresh token rotates on every use and reusing a rotated token
/// revokes the whole session family server-side, so [refresh] is strictly
/// single-flight.
class NowaveSessionManager implements NowaveAuthenticator {
  NowaveSessionManager({
    required NowaveApiClient client,
    required NowaveSessionStore store,
  }) : _client = client,
       _store = store;

  final NowaveApiClient _client;
  final NowaveSessionStore _store;

  final StreamController<NowaveAuthStatus> _status =
      StreamController<NowaveAuthStatus>.broadcast();

  NowaveSessionData? _session;
  Future<bool>? _refreshInFlight;

  /// Broadcast stream of sign-in / sign-out transitions.
  Stream<NowaveAuthStatus> get statusStream => _status.stream;

  /// The currently persisted session, or null when signed out.
  NowaveSessionData? get currentSession => _session;

  @override
  String? get accessToken => _session?.accessToken;

  /// Loads a previously persisted session into memory. Network-free; the
  /// access token is validated lazily by the first authenticated request.
  Future<void> restore() async {
    try {
      _session = await _store.read();
    } catch (e, stackTrace) {
      AppLogger.error(
        'restoring the persisted session failed',
        error: e,
        stackTrace: stackTrace,
      );
      _session = null;
    }
  }

  /// Stores a fresh token pair from `/auth/login` or `/auth/register`.
  ///
  /// The response carries no user id, so [userId] starts empty and is
  /// filled by [updateUserId] after `GET /me`.
  Future<void> adoptSession(
    NowaveTokenPair tokens, {
    required String email,
  }) async {
    _session = NowaveSessionData(
      userId: '',
      email: email,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      refreshExpiresAt: tokens.refreshExpiresAt,
    );
    await _persist();
  }

  /// Records the user id resolved via `GET /me`.
  Future<void> updateUserId(String userId) async {
    final session = _session;
    if (session == null || session.userId == userId) return;
    _session = NowaveSessionData(
      userId: userId,
      email: session.email,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      accessExpiresAt: session.accessExpiresAt,
      refreshExpiresAt: session.refreshExpiresAt,
    );
    await _persist();
  }

  /// Rotates the refresh token via `POST /auth/refresh`.
  ///
  /// Single-flight: the first caller performs the rotation and every
  /// concurrent caller awaits the same future. The in-flight slot is
  /// released on completion so a later expiry can rotate again (a stale
  /// completed future would stop all future rotations). On failure the
  /// local session is dropped and a sign-out is broadcast (the server has
  /// already revoked the family - the app must not keep acting signed in).
  @override
  Future<bool> refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    return _refreshInFlight = _refreshLocked().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _refreshLocked() async {
    final session = _session;
    if (session == null) return false;
    try {
      final data = await _client.postJson(
        '/auth/refresh',
        {'refreshToken': session.refreshToken},
        authenticate: false,
      );
      final pair = NowaveTokenPair.fromDataMap(
        (data as Map).cast<String, dynamic>(),
      );
      _session = NowaveSessionData(
        userId: session.userId,
        email: session.email,
        accessToken: pair.accessToken,
        refreshToken: pair.refreshToken,
        accessExpiresAt: pair.accessExpiresAt,
        refreshExpiresAt: pair.refreshExpiresAt,
      );
      await _persist();
      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'refreshing the session failed; signing out locally',
        error: e,
        stackTrace: stackTrace,
      );
      await clear();
      return false;
    }
  }

  /// Drops the local session and broadcasts a sign-out.
  Future<void> clear() async {
    final hadSession = _session != null;
    _session = null;
    try {
      await _store.clear();
    } catch (e, stackTrace) {
      AppLogger.error(
        'clearing the persisted session failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
    if (hadSession) {
      _status.add(const NowaveAuthSignedOut());
    }
  }

  /// Broadcasts a sign-in for the current session's user id.
  ///
  /// Called once the identity is fully resolved (after `GET /me`), so
  /// listeners never observe a sign-in without a user id.
  void notifySignedIn() {
    final userId = _session?.userId;
    if (userId != null && userId.isNotEmpty) {
      _status.add(NowaveAuthSignedIn(userId));
    }
  }

  Future<void> _persist() async {
    try {
      final session = _session;
      if (session != null) {
        await _store.write(session);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'persisting the session failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// JSON encoding helper exposed for the SQLite-backed store.
  static String encodeSession(NowaveSessionData session) =>
      jsonEncode(session.toJson());

  static NowaveSessionData? decodeSession(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    try {
      return NowaveSessionData.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }
}
