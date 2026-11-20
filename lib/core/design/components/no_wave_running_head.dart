import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/motion/no_wave_motion_policy.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// The article's title, repeated small in the app bar once the real title has
/// scrolled away - a book's running head.
///
/// A long article on a phone loses its name after the first screen: the app
/// bar holds a back arrow and two icons, and nothing says what you are
/// reading. Printed books solve this with a running head, the title set
/// small at the top of every page. This one appears only once the title has
/// passed under the app bar ([passed]), rising a little into place, and
/// leaves the same way when the title comes back.
///
/// Tapping it returns to the top of the article - the place the title it
/// stands for lives. Its accessible name says both: the title as shown, then
/// what a tap does ([semanticLabel]), so the visible words are part of the
/// name. While hidden it is not built at all, so the page carries the title
/// once, not twice.
///
/// With less motion asked for it appears and leaves in place, and the return
/// to the top is a jump.
class NoWaveRunningHead extends StatelessWidget {
  const NoWaveRunningHead({
    super.key,
    required this.title,
    required this.visible,
    required this.semanticLabel,
    this.onTap,
  });

  final String title;

  /// Whether the real title has passed under the app bar.
  final bool visible;

  /// The full accessible name: the title, then what a tap does.
  final String semanticLabel;

  /// Usually [toTop] for the scroll view the title lives in.
  final VoidCallback? onTap;

  /// Whether [anchor] - the real title - has scrolled wholly above the top
  /// of the scroll view that sent [notification].
  ///
  /// Measured on screen rather than as a scroll offset, so it stays right
  /// whatever sits above the title (a cover, a notice, categories) and
  /// whatever size the type is.
  static bool passed(BuildContext? anchor, ScrollNotification notification) {
    final title = anchor?.findRenderObject();
    final viewport = notification.context?.findRenderObject();
    if (title is! RenderBox ||
        viewport is! RenderBox ||
        !title.attached ||
        !title.hasSize ||
        !viewport.hasSize) {
      return false;
    }
    final titleBottom = title.localToGlobal(Offset(0, title.size.height)).dy;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    return titleBottom <= viewportTop;
  }

  /// Back to the top of [controller]'s scroll view: a short travel, or a
  /// jump when less motion is asked for.
  static void toTop(BuildContext context, ScrollController controller) {
    if (!controller.hasClients) return;
    if (NoWaveMotionPolicy.reducesMotion(context)) {
      controller.jumpTo(0);
      return;
    }
    unawaited(
      controller.animateTo(
        0,
        duration: NoWaveMotion.slow,
        curve: NoWaveMotionPolicy.travel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = NoWaveMotionPolicy.reducesMotion(context);
    final head = visible
        ? Semantics(
            key: const ValueKey('no-wave-running-head'),
            button: onTap != null,
            label: semanticLabel,
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: NoWaveSizes.tapTarget,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NoWaveTypography.title(
                      context,
                      size: NoWaveTypeScale.runningHead,
                    ),
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(key: ValueKey('no-wave-running-head-hidden'));
    if (still) return head;
    return AnimatedSwitcher(
      duration: NoWaveMotion.normal,
      switchInCurve: NoWaveMotionPolicy.curve,
      switchOutCurve: NoWaveMotionPolicy.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, NoWaveMotion.runningHeadRise),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: head,
    );
  }
}
