import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/reader/reader_text_size.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_controller.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Scales the article text inside [child] by [factor], on top of the system
/// text size the rest of the app follows.
///
/// Wrapping the body rather than resizing its styles one by one keeps every
/// part of the text in proportion: headings, code, captions and the voice's
/// highlight all grow together.
class ReaderTextScale extends StatelessWidget {
  const ReaderTextScale({super.key, required this.factor, required this.child});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (factor == 1) return child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: _ScaledTextScaler(media.textScaler, factor),
      ),
      child: child,
    );
  }
}

/// The system's scaler applied to text already enlarged by [factor], so a
/// nonlinear system setting stays nonlinear.
class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize * factor);

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is _ScaledTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// The text-size sheet: five steps of the same letter, in the article's
/// serif at the size each step sets the body, with the chosen one inked.
///
/// A choice applies at once - the article behind the sheet reflows while it
/// is open, so the reader judges the size on the text itself, not on a
/// sample line.
///
/// The five steps sit side by side while their names fit a fifth of the
/// width. At a large system text size they would be cut to "Def…", so the
/// steps stack into a list instead, letter beside name; and the sheet
/// scrolls, since a modal sheet stops at about half the screen.
class ReaderTextSizeSheet extends StatelessWidget {
  const ReaderTextSizeSheet({super.key, required this.controller});

  final ReaderTextSizeController controller;

  static Future<void> show(
    BuildContext context,
    ReaderTextSizeController controller,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      // Light enough that the article reflowing behind it stays readable.
      barrierColor: Colors.transparent,
      builder: (_) => ReaderTextSizeSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NoWaveSpacing.page,
          NoWaveSpacing.large,
          NoWaveSpacing.page,
          NoWaveSpacing.section,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.readerTextSizeTitle,
                style: NoWaveTypography.title(context),
              ),
            ),
            const SizedBox(height: NoWaveSpacing.xs),
            Text(
              l10n.readerTextSizeHint,
              style: NoWaveTypography.meta(context),
            ),
            const SizedBox(height: NoWaveSpacing.large),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = !_namesFit(context, constraints.maxWidth);
                return ValueListenableBuilder<ReaderTextSize>(
                  valueListenable: controller,
                  builder: (context, selected, _) {
                    final steps = [
                      for (final size in ReaderTextSize.values)
                        _SizeStep(
                          size: size,
                          selected: size == selected,
                          stacked: stacked,
                          onTap: () => controller.select(size),
                        ),
                    ];
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: steps,
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (index, step) in steps.indexed) ...[
                          if (index > 0)
                            const SizedBox(width: NoWaveSpacing.small),
                          Expanded(child: step),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Whether every step's name fits on one line in a fifth of [width], at
  /// the system text size and in the weight of the chosen step.
  static bool _namesFit(BuildContext context, double width) {
    final count = ReaderTextSize.values.length;
    final column = (width - NoWaveSpacing.small * (count - 1)) / count;
    final style = NoWaveTypography.meta(
      context,
    ).copyWith(fontWeight: FontWeight.w600);
    final l10n = context.l10n;
    for (final size in ReaderTextSize.values) {
      final painter = TextPainter(
        text: TextSpan(text: readerTextSizeName(l10n, size), style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final fits = painter.width <= column;
      painter.dispose();
      if (!fits) return false;
    }
    return true;
  }
}

class _SizeStep extends StatelessWidget {
  const _SizeStep({
    required this.size,
    required this.selected,
    required this.stacked,
    required this.onTap,
  });

  final ReaderTextSize size;
  final bool selected;

  /// One row of a list (letter, then name) rather than a column of five.
  final bool stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = readerTextSizeName(context.l10n, size);
    final ink = scheme.onSurface;
    final paper = scheme.surface;
    final key = ValueKey('reader-text-size-${size.name}');
    final nameStyle = NoWaveTypography.meta(context).copyWith(
      color: selected ? ink : scheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    final letter = SizedBox(
      height: NoWaveSizes.row,
      child: Center(
        // The letter at the size this step sets the body, through the
        // system text size like the body itself.
        child: Text(
          'A',
          style: NoWaveTypography.title(
            context,
            size: readerBodySize(size),
          ).copyWith(color: selected ? paper : ink, height: 1),
        ),
      ),
    );
    // In a list the whole line is the target; side by side, the box is,
    // and its splash stays inside its border.
    final box = Material(
      color: selected ? ink : Colors.transparent,
      shape: Border.all(
        color: selected ? ink : ink.withAlpha(NoWaveOpacity.dividerAlpha),
        width: NoWaveStroke.hairline,
      ),
      child: stacked ? letter : InkWell(key: key, onTap: onTap, child: letter),
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: stacked
          ? _row(nameStyle, name, box, key)
          : _column(nameStyle, name, box),
    );
  }

  /// The step as a fifth of a row: the letter's box, the name beneath.
  Widget _column(TextStyle style, String name, Widget box) => Column(
    children: [
      box,
      const SizedBox(height: NoWaveSpacing.xs),
      Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    ],
  );

  /// The step as a line of a list: the letter's box, the name beside it,
  /// the whole line one target.
  Widget _row(TextStyle style, String name, Widget box, Key key) => InkWell(
    key: key,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: NoWaveSizes.row, child: box),
          const SizedBox(width: NoWaveSpacing.medium),
          Expanded(child: Text(name, style: style)),
        ],
      ),
    ),
  );
}

/// The name of a text-size step, as the sheet labels it.
String readerTextSizeName(AppLocalizations l10n, ReaderTextSize size) =>
    switch (size) {
      ReaderTextSize.small => l10n.readerTextSizeSmall,
      ReaderTextSize.standard => l10n.readerTextSizeStandard,
      ReaderTextSize.large => l10n.readerTextSizeLarge,
      ReaderTextSize.extraLarge => l10n.readerTextSizeExtraLarge,
      ReaderTextSize.largest => l10n.readerTextSizeLargest,
    };
