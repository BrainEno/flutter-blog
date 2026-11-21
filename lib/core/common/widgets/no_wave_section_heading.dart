import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// An editorial heading that wraps rather than clipping at large text sizes.
///
/// The title and its [companion] (the italic gloss - "最新 *Latest*") are one
/// paragraph: they share a baseline and wrap as words do. They used to be two
/// boxes in a `Wrap` aligned by their bottoms, and a CJK serif and a Latin
/// italic have different descents, so the gloss sat a few points off the
/// title's line. The gloss is set in the muted colour, so the title is read
/// first and the gloss as an aside.
///
/// An optional [eyebrow] sits above it as a [NoWaveEyebrow]: the small
/// tracked line a magazine runs over a section title to say what kind of
/// section it is. An optional [aside] shares that line at its far end - the
/// home feed puts the day's date there, like a newspaper's dateline - and
/// drops under the eyebrow when the two do not fit side by side.
class NoWaveSectionHeading extends StatelessWidget {
  const NoWaveSectionHeading({
    super.key,
    required this.title,
    this.companion,
    this.eyebrow,
    this.aside,
  });

  final String title;
  final String? companion;
  final String? eyebrow;

  /// A short note at the end of the eyebrow line (a dateline).
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = NoWaveTypography.title(
      context,
      size: NoWaveTypeScale.heading,
    ).copyWith(height: _leading, color: scheme.onSurface);
    final eyebrow = this.eyebrow;
    final aside = this.aside;
    final companion = this.companion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (eyebrow != null || aside != null) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: NoWaveSpacing.medium,
            runSpacing: NoWaveSpacing.xs,
            children: [
              if (eyebrow != null) NoWaveEyebrow(eyebrow),
              if (aside != null)
                Text(
                  aside,
                  style:
                      NoWaveTypography.metaLabel(
                        context,
                        size: NoWaveTypeScale.eyebrow,
                        color: scheme.onSurfaceVariant,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
            ],
          ),
          const SizedBox(height: NoWaveSpacing.small),
        ],
        Semantics(
          header: true,
          child: companion == null
              ? Text(title, style: titleStyle)
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: companion,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  style: titleStyle,
                ),
        ),
      ],
    );
  }

  /// Line height of the title: tight, because a display line with the
  /// body's leading looks double-spaced when it wraps.
  static const _leading = 1.15;
}

/// The small line above a section heading: the words alone, small, muted
/// and tracked out. No leading rule - the type is distinct enough, and a mark
/// in front of every heading only delays the words.
///
/// Latin is set in capitals - the only all-caps type in the app, so it reads
/// as a label and never as a sentence. Chinese has no capitals; it keeps its
/// characters and gets a little less tracking, which is enough to set it
/// apart from body copy without breaking the words into single glyphs.
///
/// Screen readers get the text as written, not the capitals, so an English
/// line is read as words rather than spelled out as an acronym.
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
    return Text(displayText(text), semanticsLabel: text, style: style);
  }
}
