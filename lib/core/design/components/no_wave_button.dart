import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';

/// The visual weight of a [NoWaveButton].
///
/// The four roles are the whole repertoire: a screen that needs a fifth is
/// usually describing a link (use [quiet]) or two competing primaries (pick
/// one).
enum NoWaveButtonVariant {
  /// The one action a page wants the reader to take: filled accent, ink label.
  primary,

  /// A real but secondary action: square hairline border, no fill.
  secondary,

  /// Navigation and inline actions: text only, still a 48pt target.
  quiet,

  /// Irreversible or destructive actions (delete, end sessions, clear
  /// history). Uses the theme's error colour, never the accent.
  destructive,
}

/// The shared button.
///
/// Why a component instead of `ElevatedButton`/`FilledButton` at each call
/// site: Material's filled and outlined buttons default to a fully rounded
/// pill, which fights this design's square corners, and each screen was
/// re-deciding its own minimum height, padding and busy state. This widget
/// fixes the shape and the target size in one place, and adds the two states
/// screens kept getting wrong:
///
/// - **Busy.** [isLoading] keeps the label in the layout (so the button does
///   not jump) and blocks presses, and it reports as unavailable to screen
///   readers instead of staying "pressable but ignoring you". Flutter's
///   semantics has no busy flag in this version, so the state is carried by
///   the disabled announcement plus the visible spinner.
/// - **Disabled.** A null [onPressed] still keeps the 48pt target so a row of
///   buttons does not reflow when one of them becomes unavailable.
class NoWaveButton extends StatelessWidget {
  const NoWaveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = NoWaveButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
  });

  /// Visible text. Always required: an icon-only action is an `IconButton`
  /// with a tooltip, which has its own affordances.
  final String label;

  /// Null renders the disabled state. Ignored while [isLoading] is true.
  final VoidCallback? onPressed;

  final NoWaveButtonVariant variant;

  /// Leading glyph, excluded from semantics so the label is read once.
  final IconData? icon;

  /// Shows a spinner in place of the icon and blocks presses.
  final bool isLoading;

  /// Stretch to the available width (forms, dialogs on narrow screens).
  final bool expand;

  /// Overrides the spoken label when the visible text is ambiguous out of
  /// context ("删除" in a list of delete buttons).
  final String? semanticLabel;

  bool get _enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, border) = switch (variant) {
      NoWaveButtonVariant.primary => (scheme.primary, scheme.onPrimary, null),
      NoWaveButtonVariant.secondary => (
        Colors.transparent,
        scheme.onSurface,
        BorderSide(color: scheme.onSurface, width: NoWaveStroke.hairline),
      ),
      NoWaveButtonVariant.quiet => (Colors.transparent, scheme.onSurface, null),
      NoWaveButtonVariant.destructive => (
        Colors.transparent,
        scheme.error,
        BorderSide(color: scheme.error, width: NoWaveStroke.hairline),
      ),
    };
    final style = TextButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: background,
      disabledForegroundColor: scheme.onSurface.withAlpha(
        NoWaveOpacity.disabledAlpha,
      ),
      minimumSize: Size(
        expand ? double.infinity : NoWaveSizes.tapTarget,
        variant == NoWaveButtonVariant.primary
            ? NoWaveSizes.primaryAction
            : NoWaveSizes.tapTarget,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NoWaveSpacing.medium,
        vertical: NoWaveSpacing.small,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(NoWaveRadius.none)),
      ),
      side: border,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final content = _content(context, scheme);
    return Semantics(
      button: true,
      // Busy reports as "not available" rather than as a pressable button that
      // ignores you. There is no busy flag in this Flutter's semantics; keeping
      // the label and the disabled state is what a screen reader can act on.
      enabled: _enabled,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: TextButton(
        onPressed: _enabled ? onPressed : null,
        style: style,
        child: content,
      ),
    );
  }

  Widget _content(BuildContext context, ColorScheme scheme) {
    final spinner = isLoading
        ? SizedBox(
            width: NoWaveIconSize.inline,
            height: NoWaveIconSize.inline,
            child: CircularProgressIndicator(
              strokeWidth: NoWaveStroke.focus,
              // The button's own state is announced above; a second live
              // region on every button would be noise.
              semanticsLabel: '',
            ),
          )
        : null;
    final leading = spinner ?? (icon == null ? null : Icon(icon));
    final text = Text(label, textAlign: TextAlign.center);
    if (leading == null) return text;
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(child: leading),
        const SizedBox(width: NoWaveSpacing.small),
        Flexible(child: text),
      ],
    );
  }
}
