/// A server-reported active sign-in, without device fingerprints.
///
/// This read-only view intentionally does not retain the server session ID.
/// `lastRefreshedAt` is the last token refresh, not general user activity.
class AccountSession {
  const AccountSession({
    required this.createdAt,
    required this.lastRefreshedAt,
    required this.expiresAt,
    required this.current,
  });

  final DateTime createdAt;
  final DateTime? lastRefreshedAt;
  final DateTime expiresAt;
  final bool current;
}
