/// What a request to end one session actually achieved.
///
/// The server answers 404 both for "not your session" and for "already gone",
/// and from this page - whose list only contains the account's own rows - the
/// second reading is the true one. It is reported separately because it still
/// means the goal state holds: the session is not signed in any more.
enum SessionRevokeOutcome {
  /// The server ended it in this request.
  ended,

  /// It was already gone; nothing else was touched.
  alreadyEnded,
}
