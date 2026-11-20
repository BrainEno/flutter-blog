import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
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

/// The message inside every snackbar: an orange rule down the start edge,
/// then the sentence.
///
/// The bar itself is an inverted slip - ink on paper, paper on ink - with
/// square corners and no shadow. The rule is the proofreader's mark in the
/// margin: the same orange, the same [NoWaveSizes.accentRule] weight that
/// marks a position everywhere else, saying "this is about what you just
/// did". It runs the full height of the text, so a two-line message at large
/// type is marked as one. It is decoration and has no semantics; the
/// sentence is read as it was before.
class NoWaveSnackBarContent extends StatelessWidget {
  const NoWaveSnackBarContent(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            key: ValueKey('no-wave-snackbar-rule'),
            width: NoWaveSizes.accentRule,
            child: ColoredBox(color: AppPalette.orange),
          ),
          const SizedBox(width: NoWaveSpacing.medium),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
