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
    return Padding(
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
          Text(l10n.readerTextSizeHint, style: NoWaveTypography.meta(context)),
          const SizedBox(height: NoWaveSpacing.large),
          ValueListenableBuilder<ReaderTextSize>(
            valueListenable: controller,
            builder: (context, selected, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final size in ReaderTextSize.values) ...[
                  if (size.index > 0)
                    const SizedBox(width: NoWaveSpacing.small),
                  Expanded(
                    child: _SizeStep(
                      size: size,
                      selected: size == selected,
                      onTap: () => controller.select(size),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeStep extends StatelessWidget {
  const _SizeStep({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final ReaderTextSize size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = readerTextSizeName(context.l10n, size);
    final ink = scheme.onSurface;
    final paper = scheme.surface;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: Column(
        children: [
          Material(
            color: selected ? ink : Colors.transparent,
            shape: Border.all(
              color: selected ? ink : ink.withAlpha(NoWaveOpacity.dividerAlpha),
              width: NoWaveStroke.hairline,
            ),
            child: InkWell(
              key: ValueKey('reader-text-size-${size.name}'),
              onTap: onTap,
              child: SizedBox(
                height: NoWaveSizes.row,
                child: Center(
                  // The letter at the size this step sets the body, but not
                  // scaled again by the system setting: five steps that
                  // overflow their squares at large system text would say
                  // nothing about the difference between them.
                  child: Text(
                    'A',
                    textScaler: TextScaler.noScaling,
                    style: NoWaveTypography.title(
                      context,
                      size: readerBodySize(size),
                    ).copyWith(color: selected ? paper : ink, height: 1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: NoWaveSpacing.xs),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NoWaveTypography.meta(context).copyWith(
              color: selected ? ink : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
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
