import 'dart:async';

/// Reader timers are intentionally session-only. They never persist an article
/// position or start narration after an app relaunch.
enum ReadAloudSleepTimerOption {
  off(null),
  fiveMinutes(Duration(minutes: 5)),
  tenMinutes(Duration(minutes: 10)),
  fifteenMinutes(Duration(minutes: 15)),
  thirtyMinutes(Duration(minutes: 30));

  const ReadAloudSleepTimerOption(this.duration);
  final Duration? duration;
}

/// Minimal cancellable scheduling port. It keeps the controller deterministic
/// in tests without exposing Dart's concrete [Timer] to reader state.
abstract interface class ReadAloudTimerHandle {
  void cancel();
}

typedef ReadAloudTimerScheduler =
    ReadAloudTimerHandle Function(Duration delay, void Function() callback);

class _DartTimerHandle implements ReadAloudTimerHandle {
  _DartTimerHandle(this._timer);
  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

ReadAloudTimerHandle scheduleReadAloudTimer(
  Duration delay,
  void Function() callback,
) => _DartTimerHandle(Timer(delay, callback));

/// Owns exactly one sleep timer. Every selection receives a generation token,
/// so a callback that had already reached the event loop cannot stop a newer
/// reader session after the user changed or cleared the timer.
class ReadAloudSleepTimer {
  ReadAloudSleepTimer({
    ReadAloudTimerScheduler? scheduler,
    DateTime Function()? now,
  }) : _scheduler = scheduler ?? scheduleReadAloudTimer,
       _now = now ?? DateTime.now;

  final ReadAloudTimerScheduler _scheduler;
  final DateTime Function() _now;
  ReadAloudSleepTimerOption _option = ReadAloudSleepTimerOption.off;
  ReadAloudTimerHandle? _handle;
  DateTime? _deadline;
  int _generation = 0;
  bool _disposed = false;

  ReadAloudSleepTimerOption get option => _option;
  bool get isActive => _option.duration != null;
  DateTime? get deadline => _deadline;

  /// This is a display aid, not a promise of sub-second precision. A suspended
  /// mobile process can invoke the one-shot callback later, at which point the
  /// reader still stops as soon as the platform lets the app run again.
  Duration? get remaining {
    final deadline = _deadline;
    if (deadline == null) return null;
    final value = deadline.difference(_now());
    return value.isNegative ? Duration.zero : value;
  }

  void select(ReadAloudSleepTimerOption option, void Function() onExpired) {
    if (_disposed) return;
    _generation++;
    _handle?.cancel();
    _handle = null;
    _option = option;
    final duration = option.duration;
    if (duration == null) {
      _deadline = null;
      return;
    }
    _deadline = _now().add(duration);
    final generation = _generation;
    _handle = _scheduler(duration, () {
      if (_disposed || generation != _generation) return;
      _handle = null;
      _deadline = null;
      _option = ReadAloudSleepTimerOption.off;
      onExpired();
    });
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    _handle?.cancel();
    _handle = null;
    _deadline = null;
    _option = ReadAloudSleepTimerOption.off;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _handle?.cancel();
    _handle = null;
  }
}
