import 'package:belog/core/config/app_durations.dart';
import 'package:flutter/material.dart';

/// Material's own display time for a [SnackBar]; the app default.
const Duration kDefaultSnackBarDuration = AppDurations.snackBarDefault;

/// For transient feedback the user can act on again right away, such as a
/// failed search that is retried by typing (#293, #295).
const Duration kShortSnackBarDuration = AppDurations.snackBarShort;

/// The single entry point for page-level feedback (#293).
///
/// Replaces the snackbar that is currently visible instead of queueing behind
/// it, so the newest outcome is what the user reads. Pages must not call
/// `ScaffoldMessenger.of(context).showSnackBar` directly; the source scan in
/// `test/unit/core/ui_consistency_guard_test.dart` enforces that.
void showSnackBar(
  BuildContext context,
  String content, {
  SnackBarAction? action,
  Duration duration = kDefaultSnackBarDuration,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: NoWaveSnackBarContent(content),
        action: action,
        duration: duration,
      ),
    );
}

/// The message inside every snackbar: the sentence, and nothing in front of
/// it.
///
/// The bar itself is an inverted slip - ink on paper, paper on ink - with
/// square corners and no shadow; that inversion is already the whole signal
/// that this is about what you just did, so the words start at the bar's
/// own padding. Kept as one widget so every snackbar is set the same way and
/// a later change lands everywhere at once.
class NoWaveSnackBarContent extends StatelessWidget {
  const NoWaveSnackBarContent(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(message);
}
