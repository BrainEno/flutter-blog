/// The immediate identity signal used by sensitive UI. It changes before
/// storage or network work can delay the ordinary signed-in/out events.
abstract interface class NowaveSessionIdentity {
  String? get activeUserId;
  String? get accessToken;

  /// Bumped whenever the active identity is replaced or cleared - never when a
  /// token is refreshed for the same session. Callers capture it before an
  /// await and compare afterwards to tell whether their result still belongs
  /// to the session they started with.
  int get sessionGeneration;

  Stream<void> get identityChanges;
}
