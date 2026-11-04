/// Shares one in-flight operation per key until that operation completes.
///
/// A key is normally a session generation: two callers inside the same session
/// must share one rotation (replaying a rotated refresh token revokes the whole
/// session family), while a caller in a newer session must never join an older
/// session's flight. Each key's slot is released on completion - success or
/// failure - so the next caller starts a fresh attempt.
class KeyedSingleFlight<T> {
  final Map<int, Future<T>> _inFlight = <int, Future<T>>{};

  /// Joins the flight already running for [key], or starts one.
  Future<T> run(int key, Future<T> Function() operation) {
    final existing = _inFlight[key];
    if (existing != null) return existing;
    late final Future<T> flight;
    flight = Future<T>.sync(operation).whenComplete(() {
      // A newer generation may already own its own slot; only this key is
      // released here.
      if (identical(_inFlight[key], flight)) _inFlight.remove(key);
    });
    _inFlight[key] = flight;
    return flight;
  }
}
