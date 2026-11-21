import 'dart:math' as math;

import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/widgets.dart';

/// The page's text column: the full width on a phone, a centred column of
/// [maxWidth] on anything wider, and in both cases a block that *fills* the
/// column.
///
/// Seven pages used to write the same helper - `Align(topCenter)` around a
/// `ConstrainedBox(maxWidth:)` - and it had a quiet flaw: `Align` loosens the
/// width, so a child that does not stretch on its own (a heading, an
/// eyebrow, a short line of copy) shrank to its text and was then *centred*.
/// A left-aligned heading ended up floating a little right of the cards
/// under it: centred, but not quite. The child here always gets the
/// column's width, so its start edge is the column's start edge.
///
/// Things outside the column that should start where it starts - the app
/// bar's masthead, a row of tabs whose hairline runs wider than the text -
/// use [inset].
class NoWaveColumn extends StatelessWidget {
  const NoWaveColumn({
    super.key,
    required this.child,
    this.maxWidth = NoWaveSizes.contentColumn,
  });

  final Widget child;

  /// The widest the column grows.
  final double maxWidth;

  /// How far a column of [maxWidth] starts from the edge of a body [width]
  /// wide when the body keeps the page gutter around it: the gutter on a
  /// phone, the centred column's margin on a wider screen.
  static double inset(
    double width, {
    double maxWidth = NoWaveSizes.contentColumn,
  }) => math.max(NoWaveSpacing.page, (width - maxWidth) / 2);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
