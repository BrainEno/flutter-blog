/// What to do about a 401 from an authenticated request.
enum UnauthorizedReplay {
  /// Nothing may be replayed: no token was sent, or replay is disabled for
  /// this call (a rejected credential is not an expired token).
  notApplicable,

  /// Another request already rotated this session's token while this
  /// response was in flight - retry once with that token instead of rotating
  /// the same family again.
  reuseCurrentToken,

  /// The token that earned the 401 is still the current one: refresh first.
  refreshFirst,

  /// Fail closed and surface the original 401.
  surfaceOriginal,
}

/// Decides the single allowed reaction to a 401.
///
/// A refresh token rotates on every use and replaying a rotated one revokes
/// the whole session family, so this decision is deliberately narrow:
///
/// - nothing is replayed when replay is disabled or no token was sent;
/// - a token that **changed** while the response was in flight is reused only
///   when the authenticator is session-bound - the generation proves it is
///   the same account. Without that fence a new token may belong to another
///   account, so the 401 is surfaced (#104);
/// - the same token means nobody refreshed yet: refresh, then retry once.
UnauthorizedReplay decideUnauthorizedReplay({
  required String? sentToken,
  required String? currentToken,
  required bool sessionBound,
  required bool allowRefresh,
}) {
  if (!allowRefresh || sentToken == null) {
    return UnauthorizedReplay.notApplicable;
  }
  if (sessionBound && currentToken != null && currentToken != sentToken) {
    return UnauthorizedReplay.reuseCurrentToken;
  }
  if (currentToken == sentToken) {
    return UnauthorizedReplay.refreshFirst;
  }
  // The session ended (no token) or an unfenced authenticator swapped it.
  return UnauthorizedReplay.surfaceOriginal;
}
