import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:flutter/material.dart';

/// Where an article sits, as the server named it in this edition.
///
/// It differs from the tag label on purpose: a tag is a word the author typed
/// that anyone can reuse, while a category is editorial structure (ADR 0016)
/// that the desk maintains. The filled plate keeps the two from reading as one
/// list of the same thing, while the border keeps the same weight as the tag's
/// so neither looks more important.
///
/// With [onTap] it becomes a real button with a 48×48 target, like the tag
/// label; the drawn plate stays compact.
class ArticleCategoryLabel extends StatelessWidget {
  const ArticleCategoryLabel({
    super.key,
    required this.category,
    this.onTap,
  });

  /// The category as the article response described it. A ref with an empty
  /// slug or name is not addressable or printable, so callers filter it out.
  final CategoryRef category;

  /// Opens the category's article list when provided.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onSurface;
    final plate = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NoWaveSpacing.small,
        vertical: 2, // design-token-ok: badge padding, optical not a step
      ),
      decoration: BoxDecoration(
        color: AppPalette.orange.withAlpha(38),
        // The fill is what separates a category from a tag; the border keeps
        // the same weight as the tag's so neither reads as "more important".
        border: Border.all(color: foreground),
      ),
      child: Text(
        category.name,
        style: NoWaveTypography.meta(
          context,
        ).copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );

    final handler = onTap;
    if (handler == null) return plate;

    return Semantics(
      button: true,
      label: l10n.categoryBrowseSemantics(category.name),
      // The plate's own text is excluded so the screen reader hears the one
      // sentence above instead of the name twice.
      onTap: handler,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: handler,
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
          ),
          child: plate,
        ),
      ),
    );
  }
}
