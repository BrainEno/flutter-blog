import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// An editorial heading that wraps rather than clipping at large text sizes.
///
/// An optional [eyebrow] sits above it as a [NoWaveEyebrow]: the small
/// tracked line a magazine runs over a section title to say what kind of
/// section it is.
class NoWaveSectionHeading extends StatelessWidget {
  const NoWaveSectionHeading({
    super.key,
    required this.title,
    this.companion,
    this.eyebrow,
  });

  final String title;
  final String? companion;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final titleStyle = NoWaveTypography.title(context, size: 36);
    final eyebrow = this.eyebrow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          NoWaveEyebrow(eyebrow),
          const SizedBox(height: NoWaveSpacing.small),
        ],
        Semantics(
          header: true,
          child: Wrap(
            spacing: NoWaveSpacing.small,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(title, style: titleStyle),
              if (companion != null)
                Text(
                  companion!,
                  style: titleStyle.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The small line above a section heading: a short orange rule, then the
/// words, small and tracked out.
///
/// Latin is set in capitals - the only all-caps type in the app, so it reads
/// as a label and never as a sentence. Chinese has no capitals; it keeps its
/// characters and gets a little less tracking, which is enough to set it
/// apart from body copy without breaking the words into single glyphs.
///
/// Screen readers get the text as written, not the capitals, so an English
/// line is read as words rather than spelled out as an acronym. The rule is
/// decoration and has no semantics.
class NoWaveEyebrow extends StatelessWidget {
  const NoWaveEyebrow(this.text, {super.key});

  final String text;

  /// Tracking as a share of the type size: wide for capitals, narrower for
  /// CJK, whose square glyphs already carry their own space.
  static const _latinTracking = 0.14;
  static const _cjkTracking = 0.08;

  /// Whether [text] is mostly set in CJK characters (Han, kana, Hangul).
  static bool isCjk(String text) {
    var cjk = 0;
    var letters = 0;
    for (final rune in text.runes) {
      final isHan = rune >= 0x3400 && rune <= 0x9FFF;
      final isKana = rune >= 0x3040 && rune <= 0x30FF;
      final isHangul = rune >= 0xAC00 && rune <= 0xD7AF;
      if (isHan || isKana || isHangul) {
        cjk++;
        letters++;
      } else if (String.fromCharCode(rune).toUpperCase() !=
          String.fromCharCode(rune).toLowerCase()) {
        letters++;
      }
    }
    return letters > 0 && cjk * 2 >= letters;
  }

  /// [text] as it is set: capitals for Latin, unchanged for CJK.
  static String displayText(String text) =>
      isCjk(text) ? text : text.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final cjk = isCjk(text);
    const size = NoWaveTypeScale.eyebrow;
    final style =
        NoWaveTypography.metaLabel(
          context,
          size: size,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ).copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: size * (cjk ? _cjkTracking : _latinTracking),
        );
    return Row(
      children: [
        const SizedBox(
          key: ValueKey('no-wave-eyebrow-rule'),
          width: NoWaveSizes.eyebrowRule,
          height: NoWaveSizes.accentRule,
          child: ColoredBox(color: AppPalette.orange),
        ),
        const SizedBox(width: NoWaveSpacing.small),
        Flexible(
          child: Text(displayText(text), semanticsLabel: text, style: style),
        ),
      ],
    );
  }
}
