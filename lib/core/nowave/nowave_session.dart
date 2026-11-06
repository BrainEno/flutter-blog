import 'dart:async';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/session/auth_status.dart';
import 'package:belog/core/nowave/session/serial_queue.dart';
import 'package:belog/core/nowave/session/session_data.dart';
import 'package:belog/core/nowave/session/session_expiry.dart';
import 'package:belog/core/nowave/session/session_generation.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/nowave/session/session_store.dart';
import 'package:belog/core/nowave/session/single_flight.dart';
import 'package:belog/core/utils/app_logger.dart';

export 'package:belog/core/nowave/session/auth_status.dart';
export 'package:belog/core/nowave/session/session_data.dart';
export 'package:belog/core/nowave/session/session_identity.dart';
export 'package:belog/core/nowave/session/session_store.dart';

/// Owns the no-wave session lifecycle: adopting token pairs from
/// login/register, rotating the refresh token, and broadcasting
/// sign-in/sign-out to the rest of the app (the replacement for
/// Supabase's `onAuthStateChange`).
///
/// The timing rules live in separate, unit-tested units instead of in this
/// class: [SessionGeneration] is the account fence, [SerialQueue] orders
/// persistence, [KeyedSingleFlight] keeps one rotation per session, and
/// [decideSessionExpiry] is the expiry policy. What stays here is the part
/// that needs all of them at once - binding those decisions to one
/// in-memory session, the token endpoint and the sign-out result.
///
/// The refresh token rotates on every use and reusing a rotated token
/// revokes the whole session family server-side, so [refresh] is strictly
/// single-flight.
class NowaveSessionManager
    implements
        NowaveProactiveAuthenticator,
        NowaveViewerAuthenticator,
        NowaveSessionIdentity {
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
  // Synchronous so sensitive editors can invalidate their view before the
  // account-changing call yields to persistence or a network request.
  final StreamController<void> _identityChanges =
      StreamController<void>.broadcast(sync: true);

  /// Account fence: advanced before any identity change, checked after each
  /// await so an answer that belongs to a replaced session is dropped.
  final SessionGeneration _generation = SessionGeneration();

  /// Persistence is serialized so an old write cannot finish after sign-out or
  /// after a newer account has been written to the same platform store.
  final SerialQueue _storeQueue = SerialQueue();

  /// One rotation per session generation; a newer session never joins the
  /// previous session's flight.
  final KeyedSingleFlight<bool> _refreshFlights = KeyedSingleFlight<bool>();

  NowaveSessionData? _session;

  @override
  Stream<void> get identityChanges => _identityChanges.stream;

  /// Changes whenever the active identity is replaced or cleared, but not
  /// when a token is refreshed for the same session.
  @override
  int get sessionGeneration => _generation.value;

  /// Broadcast stream of sign-in / sign-out transitions.
  Stream<NowaveAuthStatus> get statusStream => _status.stream;

  /// The currently persisted session, or null when signed out.
  NowaveSessionData? get currentSession => _session;

  @override
  String? get accessToken => _session?.accessToken;

  @override
  String? get activeUserId => _session?.userId;

  /// Loads a previously persisted session into memory. Network-free; the
  /// access token is validated lazily by the first authenticated request.
  Future<void> restore() async {
    final generation = _generation.advance();
    _identityChanges.add(null);
    try {
      final restored = await _storeQueue.run(_store.read);
      if (_generation.isCurrent(generation)) _session = restored;
    } catch (e, stackTrace) {
      AppLogger.error(
        'restoring the persisted session failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (_generation.isCurrent(generation)) _session = null;
    }
  }

  /// Stores a fresh token pair from `/auth/login` or `/auth/register`.
  ///
  /// The response carries no user id, so [userId] starts empty and is
  /// filled by [updateUserId] after `GET /me`.
  ///
  /// Returns whether the pair reached the platform store. A sign-in that
  /// cannot be persisted is not durable - the caller must not present it as a
  /// success, because the next start would find an empty store (#100).
  Future<bool> adoptSession(
    NowaveTokenPair tokens, {
    required String email,
  }) async {
    _generation.advance();
    _session = NowaveSessionData(
      userId: '',
      email: email,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      refreshExpiresAt: tokens.refreshExpiresAt,
    );
    _identityChanges.add(null);
    return _persist();
  }

  /// Records the user id resolved via `GET /me`.
  Future<void> updateUserId(String userId) async {
    final session = _session;
    if (session == null || session.userId == userId) return;
    _session = session.copyWith(userId: userId);
    _identityChanges.add(null);
    await _persist();
  }

  /// Records the address the account holds after a change.
  ///
  /// Unlike [updateUserId] this is not an identity change: the same account
  /// stays signed in on the same tokens, so no identity listener is notified.
  /// It is still persisted, because the offline start path reads the address
  /// from the stored session.
  Future<void> updateEmail(String email) async {
    final session = _session;
    if (session == null || email.isEmpty || session.email == email) return;
    _session = session.copyWith(email: email);
    await _persist();
  }

  /// Rotates the refresh token via `POST /auth/refresh`.
  ///
  /// Single-flight per active session: concurrent callers share one
  /// rotation and the slot is released on completion. An authorization
  /// rejection clears that same session. A failure whose outcome is unknown
  /// (timeout, dropped connection, 5xx) keeps the session but marks the
  /// refresh token spent, so it is never sent again; asking for another
  /// rotation after that ends the session locally instead (#101).
  /// Responses belonging to a replaced session are ignored.
  @override
  Future<bool> refresh() {
    final generation = _generation.value;
    return _refreshFlights.run(generation, () => _refreshLocked(generation));
  }

  /// Proactively rotates the access token when it is about to expire,
  /// so requests do not pay a 401 round-trip on every expiry.
  ///
  /// Failure policy differs from [refresh] on purpose: a transport or
  /// server error leaves the session alone (the still-valid access token
  /// is used and the 401 path stays the authority for unrecoverable
  /// sessions). A refresh token that has already expired - or that a
  /// previous unknown outcome retired - never triggers a network call; the
  /// session lives on its access token and ends locally once that expires.
  ///
  /// The decision itself is [decideSessionExpiry]; this method only carries
  /// out its answer.
  @override
  Future<bool> ensureFreshAccess() async {
    final session = _session;
    if (session == null) return false;
    final action = decideSessionExpiry(
      session: session,
      now: _now(),
      leadTime: refreshLeadTime,
    );
    switch (action) {
      case SessionExpiryAction.reuseAccessToken:
      case SessionExpiryAction.keepAccessTokenOnly:
        return false;
      case SessionExpiryAction.endWithExpiredRefreshToken:
        AppLogger.debug(
          'refresh token already expired; ending the session locally',
        );
        await clear();
        return false;
      case SessionExpiryAction.endWithSpentRefreshToken:
        // There is no token left that may be sent safely: the access token is
        // the only thing keeping this session alive, and it is gone.
        AppLogger.debug(
          'access token expired and the refresh token is spent; '
          'ending the session locally',
        );
        await clear();
        return false;
      case SessionExpiryAction.rotate:
        return refresh();
    }
  }

  Future<bool> _refreshLocked(int generation) async {
    final session = _session;
    if (session == null) return false;
    if (session.refreshTokenSpent) {
      // This token may already have been rotated server-side, and replaying a
      // rotated token revokes the whole family. A caller only asks for a
      // rotation when the access token cannot carry the session (the 401 path)
      // or the proactive path skips spent sessions - so end it locally and
      // let the user authenticate again.
      AppLogger.debug(
        'refresh token already spent; ending the session instead of resending',
      );
      await clear();
      return false;
    }
    try {
      final data = await _client.postJson('/auth/refresh', {
        'refreshToken': session.refreshToken,
      }, authenticate: false);
      final pair = NowaveTokenPair.fromDataMap(
        (data as Map).cast<String, dynamic>(),
      );
      final current = _session;
      if (!_generation.isCurrent(generation) ||
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
      if (!await _persist()) {
        // The rotated pair lives only in memory while the store still holds
        // the token the server just spent. Removing that copy is the only way
        // a restart cannot replay it; the in-memory session keeps working
        // until it is closed, then the user signs in again.
        AppLogger.error(
          'the rotated session could not be persisted; dropping the stored '
          'copy so a restart cannot replay the spent token',
        );
        try {
          await _storeQueue.run(_store.clear);
        } catch (e, stackTrace) {
          AppLogger.error(
            'removing the stale stored session failed; a restart may replay '
            'the spent refresh token',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }
      return _generation.isCurrent(generation);
    } catch (e, stackTrace) {
      if (!_generation.isCurrent(generation)) return false;
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
        // Transport or server error: the server may already have rotated the
        // token before answering. Keep the session (its access token may
        // still be good) but retire the refresh token, or the next attempt
        // would look like a replay and revoke the family.
        AppLogger.error(
          'refreshing the session failed with an unknown outcome; the refresh '
          'token will not be reused',
          error: e,
          stackTrace: stackTrace,
        );
        await _markRefreshTokenSpent(generation);
      }
      return false;
    }
  }

  /// Retires the current refresh token after a rotation with an unknown
  /// outcome and persists that decision, so a restart cannot replay it.
  Future<void> _markRefreshTokenSpent(int generation) async {
    final session = _session;
    if (!_generation.isCurrent(generation) || session == null) return;
    if (session.refreshTokenSpent) return;
    _session = session.copyWith(refreshTokenSpent: true);
    await _persist();
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
    await clearForSignOut();
  }

  /// Drops the local session and reports whether a restart could bring it
  /// back.
  ///
  /// The in-memory session is gone either way - the user is signed out of
  /// this launch - but [SessionClearResult.failed] means the durable copy
  /// survived, so the caller must not present the sign-out as complete
  /// (#102).
  Future<SessionClearResult> clearForSignOut() async {
    final hadSession = _session != null;
    final generation = _generation.advance();
    _session = null;
    _identityChanges.add(null);
    var result = SessionClearResult.failed;
    final store = _store;
    try {
      if (store is NowaveSessionSignOutStore) {
        result = await _storeQueue.run(store.clearForSignOut);
      } else {
        await _storeQueue.run(store.clear);
        result = SessionClearResult.cleared;
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'clearing the persisted session failed',
        error: e,
        stackTrace: stackTrace,
      );
      result = SessionClearResult.failed;
    }
    if (result == SessionClearResult.failed) {
      AppLogger.error(
        'the local session could not be removed from storage; a restart may '
        'restore the account',
      );
    }
    if (hadSession && _generation.isCurrent(generation) && _session == null) {
      _status.add(const NowaveAuthSignedOut());
    }
    return result;
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

  /// Writes the current session and reports whether that worked.
  ///
  /// The in-memory session is kept either way: a storage hiccup must not sign
  /// a working session out mid-use. Callers that create a *new* session (see
  /// [adoptSession]) treat a `false` as "not durable" instead.
  Future<bool> _persist() async {
    final session = _session;
    if (session == null) return true;
    try {
      await _storeQueue.run(() => _store.write(session));
      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'persisting the session failed',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
