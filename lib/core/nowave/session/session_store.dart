import 'package:belog/core/nowave/session/session_data.dart';

/// Durable storage for the session. The app normally uses platform secure
/// storage; a legacy SQLite store remains a migration source and fallback
/// when secure storage is unavailable. See the audit for failure limitations.
abstract class NowaveSessionStore {
  Future<NowaveSessionData?> read();
  Future<void> write(NowaveSessionData session);
  Future<void> clear();
}

/// How much of a sign-out actually reached durable storage.
///
/// Signing out has two halves: the server-side revocation (best-effort) and
/// the local clear. The local clear is the one that decides whether the
/// account can come back on the next launch, so its result must not be
/// reduced to a log line (#102).
enum SessionClearResult {
  /// No copy of the session remains and no restart can restore it.
  cleared,

  /// The app can no longer restore the session, but a copy survived in a
  /// medium that is currently unwritable. The surviving copy is disowned, so
  /// it is residue rather than a session - still not the same as a clean
  /// clear, and the user is told so.
  disowned,

  /// Not even the record that disowns the copies could be written: a restart
  /// may restore the account.
  failed,
}

/// A store that can report *how* durable a sign-out was.
///
/// Kept separate from [NowaveSessionStore] so existing stores and test
/// doubles stay valid; the session manager asks for it when available.
abstract interface class NowaveSessionSignOutStore
    implements NowaveSessionStore {
  Future<SessionClearResult> clearForSignOut();
}
