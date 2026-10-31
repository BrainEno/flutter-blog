import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/utils/app_logger.dart';

/// A persisted no-wave session: the rotated token pair plus the identity
/// the app caches locally. The current backend can return an e-mail and
/// verification status in `GET /me`, but this client only reads the id;
/// the UI still uses the address entered at sign-in.
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

  /// Copy with the fields that change over a session's lifetime.
  NowaveSessionData copyWith({
    String? userId,
    String? email,
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    DateTime? refreshExpiresAt,
  }) {
    return NowaveSessionData(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
      refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
    );
  }

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

/// Durable storage for the session. The app normally uses platform secure
/// storage; a legacy SQLite store remains a migration source and fallback
/// when secure storage is unavailable. See the audit for failure limitations.
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
class NowaveSessionManager
    implements NowaveProactiveAuthenticator, NowaveSessionBoundAuthenticator {
  NowaveSessionManager({
    required NowaveApiClient client,
    required NowaveSessionStore store,
    this.refreshLeadTime = const Duration(seconds: 30),
    DateTime Function() now = DateTime.now,
  }) : _client = client,
       _store = store,
       _now = now;

  final NowaveApiClient _client;
  final NowaveSessionStore _store;

  /// How far before its expiry the access token is rotated proactively
  /// by [ensureFreshAccess].
  final Duration refreshLeadTime;

  /// Injectable clock so expiry decisions are testable.
  final DateTime Function() _now;

  final StreamController<NowaveAuthStatus> _status =
      StreamController<NowaveAuthStatus>.broadcast();

  NowaveSessionData? _session;
  Future<bool>? _refreshInFlight;
  int? _refreshGeneration;
  int _sessionGeneration = 0;
  Future<void> _storeTail = Future<void>.value();

  /// Changes whenever the active identity is replaced or cleared, but not
  /// when a token is refreshed for the same session.
  @override
  int get sessionGeneration => _sessionGeneration;

  /// Serializes persistence so an old write cannot finish after sign-out or
  /// after a newer account has been written to the same platform store.
  Future<T> _withStore<T>(Future<T> Function() operation) {
    final result = _storeTail.then((_) => operation());
    _storeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  /// Broadcast stream of sign-in / sign-out transitions.
  Stream<NowaveAuthStatus> get statusStream => _status.stream;

  /// The currently persisted session, or null when signed out.
  NowaveSessionData? get currentSession => _session;

  @override
  String? get accessToken => _session?.accessToken;

  /// Loads a previously persisted session into memory. Network-free; the
  /// access token is validated lazily by the first authenticated request.
  Future<void> restore() async {
    final generation = ++_sessionGeneration;
    try {
      final restored = await _withStore(_store.read);
      if (generation == _sessionGeneration) _session = restored;
    } catch (e, stackTrace) {
      AppLogger.error(
        'restoring the persisted session failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (generation == _sessionGeneration) _session = null;
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
    _sessionGeneration++;
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
    _session = session.copyWith(userId: userId);
    await _persist();
  }

  /// Rotates the refresh token via `POST /auth/refresh`.
  ///
  /// Single-flight per active session: concurrent callers share one
  /// rotation and the slot is released on completion. An authorization
  /// rejection clears that same session; transient failures leave it intact.
  /// Responses belonging to a replaced session are ignored.
  @override
  Future<bool> refresh() {
    final generation = _sessionGeneration;
    final inFlight = _refreshInFlight;
    if (inFlight != null && _refreshGeneration == generation) {
      return inFlight;
    }
    late final Future<bool> flight;
    flight = _refreshLocked(generation).whenComplete(() {
      if (identical(_refreshInFlight, flight)) {
        _refreshInFlight = null;
        _refreshGeneration = null;
      }
    });
    _refreshGeneration = generation;
    _refreshInFlight = flight;
    return flight;
  }

  /// Proactively rotates the access token when it is about to expire,
  /// so requests do not pay a 401 round-trip on every expiry.
  ///
  /// Failure policy differs from [refresh] on purpose: a transport or
  /// server error leaves the session alone (the still-valid access token
  /// is used and the 401 path stays the authority for unrecoverable
  /// sessions). A refresh token that has already expired ends the session
  /// locally without any network call.
  @override
  Future<bool> ensureFreshAccess() async {
    final session = _session;
    if (session == null) return false;
    final currentTime = _now();
    if (session.accessToken.isNotEmpty &&
        session.accessExpiresAt.isAfter(currentTime.add(refreshLeadTime))) {
      return false;
    }
    if (!session.refreshExpiresAt.isAfter(currentTime)) {
      AppLogger.debug(
        'refresh token already expired; ending the session locally',
      );
      await clear();
      return false;
    }
    return refresh();
  }

  Future<bool> _refreshLocked(int generation) async {
    final session = _session;
    if (session == null) return false;
    try {
      final data = await _client.postJson('/auth/refresh', {
        'refreshToken': session.refreshToken,
      }, authenticate: false);
      final pair = NowaveTokenPair.fromDataMap(
        (data as Map).cast<String, dynamic>(),
      );
      final current = _session;
      if (generation != _sessionGeneration ||
          current == null ||
          current.refreshToken != session.refreshToken) {
        return false;
      }
      // Preserve identity updates made while the rotation was in flight.
      _session = current.copyWith(
        accessToken: pair.accessToken,
        refreshToken: pair.refreshToken,
        accessExpiresAt: pair.accessExpiresAt,
        refreshExpiresAt: pair.refreshExpiresAt,
      );
      await _persist();
      return generation == _sessionGeneration;
    } catch (e, stackTrace) {
      if (generation != _sessionGeneration) return false;
      if (_isAuthRejection(e)) {
        // The backend rejected the rotated refresh token: the session
        // family is revoked server-side, the app must stop acting
        // signed in.
        AppLogger.error(
          'refreshing the session was rejected; signing out locally',
          error: e,
          stackTrace: stackTrace,
        );
        await clear();
      } else {
        // Transport or server error: keep the session and let callers
        // retry with the current access token.
        AppLogger.error(
          'refreshing the session failed; keeping the session',
          error: e,
          stackTrace: stackTrace,
        );
      }
      return false;
    }
  }

  /// Whether [error] is the backend rejecting the refresh token (revoked
  /// session family) rather than a transport or server error.
  bool _isAuthRejection(Object error) {
    if (error is! NowaveApiException) return false;
    return error.statusCode == HttpStatus.unauthorized ||
        error.code == 'UNAUTHENTICATED';
  }

  /// Drops the local session and broadcasts a sign-out.
  Future<void> clear() async {
    final hadSession = _session != null;
    final generation = ++_sessionGeneration;
    _session = null;
    try {
      await _withStore(_store.clear);
    } catch (e, stackTrace) {
      AppLogger.error(
        'clearing the persisted session failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
    if (hadSession && generation == _sessionGeneration && _session == null) {
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
    final session = _session;
    if (session == null) return;
    try {
      await _withStore(() => _store.write(session));
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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return NowaveSessionData.fromJson(decoded);
    } on FormatException {
      // A corrupt payload (bad JSON, unparsable dates) reads as "no
      // session" rather than crashing every launch.
      return null;
    }
  }
}
