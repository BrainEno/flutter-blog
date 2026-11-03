/// Monotonic ordering of authentication intents: sign-in, sign-up, sign-out
/// and session restore.
///
/// The session manager's generation counter orders *adoptions* of a session,
/// which is not the same question as "which attempt did the user start last?".
/// Two sign-ins launched back to back both adopt, and the one whose HTTP
/// response arrives last wins - so a slow first attempt could replace the
/// account the user chose afterwards (issue #99).
///
/// Every intent gets an increasing id; only the newest one may change the
/// session, the profile cache or [AppUserCubit]. Older responses are dropped
/// instead of being replayed or reported as "never submitted": the server may
/// still have acted on the request that was sent.
class AuthIntentGate {
  int _issued = 0;
  int _current = 0;

  /// Starts a new intent and makes it the current one.
  ///
  /// Call it synchronously before dispatching the work, never after an
  /// `await`: the id handed out here is what the fenced work compares against.
  int begin() => _current = ++_issued;

  /// The newest intent id, or 0 when no intent has started yet.
  int get current => _current;

  /// Whether [intent] is still the newest intent.
  bool isCurrent(int intent) => intent != 0 && intent == _current;

  /// Whether [intent] is still the newest intent, treating `null` (a caller
  /// that does not take part in intent ordering) as current.
  bool allows(int? intent) => intent == null || isCurrent(intent);
}
