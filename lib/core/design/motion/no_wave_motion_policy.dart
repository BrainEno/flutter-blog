import 'package:flutter/widgets.dart';

/// How the app answers the platform's "less motion" settings.
///
/// Two switches mean the same thing to a reader: the OS animation switch, and
/// a screen reader. The second one is easy to forget - VoiceOver and TalkBack
/// explore one element at a time, and a page that slides or fades underneath
/// moves the thing being read. Folding both into one predicate means no call
/// site has to remember which of the two it checked.
///
/// The policy resolves a duration; it does not decide what a widget does with
/// it. `Duration.zero` is Flutter's own "arrive now": an animation controller
/// finishes on the next frame, and a transition that is not built at all is not
/// a transition. Prefer the second: skipping a fade is cheaper than running it
/// at zero length.
///
/// The curves live here rather than in the tokens for the same reason the
/// predicate does: they are how the app *moves*, and both are read from a
/// context-aware helper so a screen never writes `Curves.easeOut` itself.
abstract final class NoWaveMotionPolicy {
  /// Whether this context asks for less motion.
  static bool reducesMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  /// [duration] as this context allows it: unchanged, or [Duration.zero].
  static Duration resolve(BuildContext context, Duration duration) =>
      reducesMotion(context) ? Duration.zero : duration;

  /// Content entering or leaving: starts quickly, settles softly, and never
  /// overshoots. An elastic arrival reads as a toy next to this type.
  static const curve = Curves.fastOutSlowIn;

  /// Something travelling to a place - a caret following the read-aloud voice.
  /// Decelerates into the destination instead of easing in and out, so the eye
  /// is never waiting on the start.
  static const travel = Curves.easeOut;
}
