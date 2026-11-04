/// The account fence: a monotonic counter bumped whenever the active identity
/// is replaced or cleared.
///
/// Every multi-step operation captures [value] before its first await and asks
/// [isCurrent] afterwards. A stale answer is then dropped instead of being
/// applied to a different account - the class exists so that fence is one
/// tested decision rather than a comparison repeated at each call site.
class SessionGeneration {
  int _value = 0;

  /// The fence to capture now.
  int get value => _value;

  /// Invalidates every previously captured fence and returns the new one.
  int advance() => ++_value;

  /// Whether [generation] is still the current one.
  bool isCurrent(int generation) => generation == _value;
}
