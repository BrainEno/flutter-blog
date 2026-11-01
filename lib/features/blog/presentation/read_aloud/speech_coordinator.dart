import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';

abstract interface class SpeechOwner {
  void speechWasReplaced();
}

/// One system synthesizer is shared across reader routes. Commands are
/// serialized, and a departing page can never stop a newer page's speech.
class SpeechCoordinator {
  SpeechCoordinator(this.engine);

  final SpeechEngine engine;
  Future<List<SpeechVoice>>? _initialization;
  Future<void> _tail = Future<void>.value();
  SpeechOwner? _owner;
  int _ownership = 0;
  int _utterance = 0;

  Future<List<SpeechVoice>> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;
    late final Future<List<SpeechVoice>> pending;
    pending = engine.initialize().catchError((Object error, StackTrace stack) {
      if (identical(_initialization, pending)) _initialization = null;
      Error.throwWithStackTrace(error, stack);
    });
    _initialization = pending;
    return pending;
  }

  String nextUtteranceId() => '${++_utterance}';

  /// A navigation callback may capture this identity and stop only the page
  /// that was active when navigation began, never a subsequently opened page.
  SpeechOwner? get owner => _owner;

  Future<void> stopIfCurrent(SpeechOwner? expected) {
    if (expected == null || !identical(_owner, expected)) {
      return Future<void>.value();
    }
    expected.speechWasReplaced();
    return release(expected);
  }

  void claim(SpeechOwner owner) {
    if (identical(_owner, owner)) return;
    final old = _owner;
    _owner = owner;
    _ownership++;
    old?.speechWasReplaced();
  }

  Future<void> perform(
    SpeechOwner owner,
    bool Function() valid,
    Future<void> Function(SpeechEngine engine, bool Function() valid) action,
  ) {
    final token = _ownership;
    bool stillValid() =>
        identical(_owner, owner) && token == _ownership && valid();
    return _enqueue(() async {
      if (stillValid()) await action(engine, stillValid);
    });
  }

  Future<void> release(SpeechOwner owner) {
    if (!identical(_owner, owner)) return Future<void>.value();
    _owner = null;
    final token = ++_ownership;
    return _enqueue(() async {
      if (_owner == null && token == _ownership) await engine.stop();
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
