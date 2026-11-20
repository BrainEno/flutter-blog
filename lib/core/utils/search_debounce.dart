import 'dart:async';

import 'package:belog/core/config/app_durations.dart';

/// The pause after the last keystroke before a search box queries (#292).
///
/// Every search field in the app - articles, authors and message participants
/// - waits the same 300ms, so typing feels the same everywhere and a change
/// to the delay happens in one place.
const Duration kSearchDebounceDelay = AppDurations.searchDebounce;

/// Runs only the last action scheduled within [delay].
///
/// Each [call] cancels the pending action, if any, and schedules the new one.
/// Owners must [cancel] (or [dispose]) when the query is submitted, cleared
/// or the widget goes away; a pending action that fires after `dispose` would
/// otherwise touch a dead `State`. Callbacks should still check `mounted` or
/// a generation counter, because the debounce cannot know whether the result
/// is still wanted once it has started.
class SearchDebounce {
  SearchDebounce({this.delay = kSearchDebounceDelay});

  /// How long to wait after the most recent [call].
  final Duration delay;

  Timer? _timer;

  /// Whether an action is scheduled and has not run or been cancelled yet.
  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [action] after [delay], replacing any pending action.
  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      action();
    });
  }

  /// Drops the pending action, if any. Safe to call repeatedly.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Alias of [cancel] for `State.dispose`, where the intent reads better.
  void dispose() => cancel();
}
