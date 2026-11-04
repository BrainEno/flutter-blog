/// Auth status broadcast by the session manager: the replacement for
/// Supabase's `onAuthStateChange`.
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
