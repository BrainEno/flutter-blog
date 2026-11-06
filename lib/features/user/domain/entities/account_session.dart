/// A server-reported active sign-in, without device fingerprints.
///
/// `lastRefreshedAt` is the last token refresh, not general user activity.
class AccountSession {
  const AccountSession({
    required this.id,
    required this.createdAt,
    required this.lastRefreshedAt,
    required this.expiresAt,
    required this.current,
  });

  /// The server's opaque handle for this session.
  ///
  /// It is only here so one row can be ended by id. It is never shown, logged
  /// or persisted, and this class overrides no `toString`: a session id names a
  /// live credential, so it must not reach a log line through an accidental
  /// string interpolation of the whole object.
  final String id;

  final DateTime createdAt;
  final DateTime? lastRefreshedAt;
  final DateTime expiresAt;
  final bool current;
}
