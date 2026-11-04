import 'package:belog/core/nowave/session/session_data.dart';

/// What the app should do with the tokens it currently holds.
enum SessionExpiryAction {
  /// The access token is comfortably valid: use it, no network call.
  reuseAccessToken,

  /// Ask `POST /auth/refresh` for a new pair.
  rotate,

  /// The refresh token is spent but the access token still works: keep the
  /// session alive without any network call and let it end when the access
  /// token expires.
  keepAccessTokenOnly,

  /// The refresh token itself has expired: nothing can renew the session.
  endWithExpiredRefreshToken,

  /// The refresh token is spent and the access token has expired too: no safe
  /// token is left to send.
  endWithSpentRefreshToken,
}

/// Decides what [session] needs at [now].
///
/// Pure on purpose: the whole timing policy is a mapping from (access expiry,
/// refresh expiry, spent flag) to one action, so it can be tested exhaustively
/// without a clock, a store or a network. Order matters and mirrors the
/// backend's constraints: a valid access token is always used first, an
/// expired refresh token always ends the session, and a spent refresh token is
/// never sent - it only leaves the access token as the remaining life.
SessionExpiryAction decideSessionExpiry({
  required NowaveSessionData session,
  required DateTime now,
  required Duration leadTime,
}) {
  if (session.accessToken.isNotEmpty &&
      session.accessExpiresAt.isAfter(now.add(leadTime))) {
    return SessionExpiryAction.reuseAccessToken;
  }
  if (!session.refreshExpiresAt.isAfter(now)) {
    return SessionExpiryAction.endWithExpiredRefreshToken;
  }
  if (session.refreshTokenSpent) {
    return session.accessExpiresAt.isAfter(now)
        ? SessionExpiryAction.keepAccessTokenOnly
        : SessionExpiryAction.endWithSpentRefreshToken;
  }
  return SessionExpiryAction.rotate;
}
