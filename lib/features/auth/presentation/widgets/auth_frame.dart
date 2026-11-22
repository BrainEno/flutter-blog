import 'package:belog/core/common/widgets/language_menu_button.dart';
import 'package:belog/core/common/widgets/no_wave_masthead.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/design/components/no_wave_column.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:flutter/material.dart';

/// The page every sign-in, sign-up and recovery screen is set on.
///
/// The same composition as the tabs a reader already knows - the masthead in
/// the app bar, an editorial heading under it, then the content on one left
/// edge - instead of a centred bold word over a stack of boxed fields. The
/// first screen many people meet should look like the rest of the app.
///
/// The column stops at [NoWaveSizes.formMeasure]; on a wider screen it is
/// centred and the masthead starts on its edge.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.title,
    required this.child,
    this.companion,
    this.lead,
    this.languageMenu = false,
  });

  /// The heading, in the same type as every tab's.
  final String title;

  /// The italic word after the title, when the page has one.
  final String? companion;

  /// A sentence under the heading, for a page that has to explain itself
  /// before it asks for anything (recovery).
  final String? lead;

  /// Offers the language menu: the screens a signed-out reader starts on
  /// are the only place it can be changed before the profile tab exists.
  final bool languageMenu;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gutter = NoWaveColumn.inset(
      MediaQuery.sizeOf(context).width,
      maxWidth: NoWaveSizes.formMeasure,
    );
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final lead = this.lead;
    return Scaffold(
      appBar: AppBar(
        // Beside a back arrow the masthead follows it; alone it starts on
        // the column's edge, like the heading and fields under it.
        titleSpacing: canGoBack ? 0 : gutter,
        title: const NoWaveMasthead(),
        actions: [
          if (languageMenu) const LanguageMenuButton(),
          const SizedBox(width: NoWaveSpacing.small),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            NoWaveSpacing.large,
            gutter,
            NoWaveSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // No strapline over the title: the title already says what the
              // page is for, and a sentence of marketing above it only delays
              // the fields.
              NoWaveSectionHeading(title: title, companion: companion),
              if (lead != null) ...[
                const SizedBox(height: NoWaveSpacing.medium),
                Text(
                  lead,
                  style:
                      NoWaveTypography.title(
                        context,
                        size: NoWaveTypeScale.sectionTitle,
                      ).copyWith(
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: NoWaveSpacing.section),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// A line that leads somewhere else in the flow: a quiet question and the
/// answer as the one bold word ("No account yet? **Sign up**"), with a
/// full-height target.
class AuthLink extends StatelessWidget {
  const AuthLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.prompt,
    this.alignment = AlignmentDirectional.center,
    this.quiet = false,
  });

  /// A way out rather than a step forward ("browse without signing in"):
  /// set in the muted tone at regular weight, so the form's own actions
  /// stay the loudest words on the page.
  final bool quiet;

  /// Where on the column the line sits. Centred by default: the lines
  /// under a full-width button hang from its middle, as one group with it.
  /// A link that belongs to a field ("forgot password" under the password)
  /// keeps to that field's end instead.
  final AlignmentDirectional alignment;

  /// The muted part before the link, already spaced; omitted for a bare
  /// link.
  final String? prompt;

  /// The words that act.
  final String label;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = NoWaveTypography.meta(
      context,
    ).copyWith(fontSize: NoWaveTypeScale.label);
    final prompt = this.prompt;
    return Align(
      alignment: alignment,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          padding: EdgeInsets.zero,
          minimumSize: const Size(NoWaveSizes.tapTarget, NoWaveSizes.tapTarget),
          alignment: alignment,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              if (prompt != null)
                TextSpan(
                  text: prompt,
                  style: base.copyWith(color: scheme.onSurfaceVariant),
                ),
              TextSpan(
                text: label,
                style: base.copyWith(
                  color: quiet ? scheme.onSurfaceVariant : scheme.onSurface,
                  fontWeight: quiet ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
            ],
          ),
          // A line that wraps (a long prompt at a large text size) keeps
          // the same edge as the one-line version.
          textAlign: switch (alignment.start) {
            < 0 => TextAlign.start,
            > 0 => TextAlign.end,
            _ => TextAlign.center,
          },
        ),
      ),
    );
  }
}
