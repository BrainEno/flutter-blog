/// Runs asynchronous operations one at a time, in call order.
///
/// Persistence is the motivating case: a slow write for the previous account
/// must not land after the sign-out or after the next account's write. The
/// queue only orders calls - it never swallows an operation's result or error,
/// which are returned to that operation's caller, and a failed operation does
/// not block the ones behind it.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// Appends [operation] to the queue and returns its own result.
  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
