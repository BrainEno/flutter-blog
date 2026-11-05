/// Sends what the publish queue owes the server (issue #23).
///
/// The interface lets the interface layer start a send without knowing how a
/// send is performed, and the queue screen and the editor share exactly the
/// path the background retry uses.
abstract interface class PublishQueueDrainer {
  /// Sends every due entry for the signed-in account and returns how many the
  /// server accepted. Doing nothing (no session, offline, nothing due) is a
  /// normal, silent result.
  Future<int> drain();
}
