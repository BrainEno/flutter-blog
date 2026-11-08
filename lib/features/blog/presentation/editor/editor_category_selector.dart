import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:flutter/material.dart';

/// The category row of the editor: one choice, from the server's own catalog.
///
/// Categories are editorial structure (ADR 0016). The desk therefore never
/// invents one: it shows what `GET /categories` returned and reports the id of
/// the chip the author picked. Tapping the selected chip clears it, because
/// "no category" is a real answer.
///
/// A row the author never touches reports nothing at all - the page then omits
/// `categoryIds` from the write, and an article whose category was set on the
/// web keeps it.
class EditorCategorySelector extends StatelessWidget {
  const EditorCategorySelector({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.isLoading,
    required this.hasFailed,
    required this.onSelected,
    required this.onRetry,
  });

  final List<CategoryRef> categories;

  /// The id currently selected, or null for "none".
  final String? selectedId;

  final bool isLoading;
  final bool hasFailed;

  /// Reports the next selection; null means the author cleared it.
  final ValueChanged<String?> onSelected;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final muted = isDarkMode ? AppPalette.mutedOnInk : AppPalette.mutedOnPaper;
    final borderColor = muted.withAlpha((0.7 * 255).toInt());
    final backgroundColor = isDarkMode
        ? AppPalette.surfaceOnInk.withAlpha((0.6 * 255).toInt())
        : AppPalette.surfaceOnPaper.withAlpha((0.4 * 255).toInt());
    final unselectedLabel = isDarkMode ? AppPalette.paper : AppPalette.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.editorCategoryTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        Text(
          context.l10n.editorCategoryHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: NoWaveSpacing.small),
        if (isLoading)
          Semantics(
            liveRegion: true,
            child: Text(
              context.l10n.editorCategoryLoading,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else if (hasFailed)
          Row(
            children: [
              Flexible(
                child: Text(
                  context.l10n.editorCategoryFailed,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: Text(context.l10n.editorCategoryRetry),
              ),
            ],
          )
        else if (categories.isEmpty)
          Text(
            context.l10n.editorCategoryEmpty,
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: NoWaveSpacing.small,
            runSpacing: NoWaveSpacing.small,
            children: [
              for (final category in categories.where(
                (category) => category.id.isNotEmpty,
              ))
                InputChip(
                  label: Text(
                    category.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: category.id == selectedId
                          ? AppPalette.ink
                          : unselectedLabel,
                    ),
                  ),
                  selected: category.id == selectedId,
                  elevation: 0,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(
                    vertical: NoWaveSpacing.small,
                    horizontal: NoWaveSpacing.small,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                    side: BorderSide(color: borderColor),
                  ),
                  backgroundColor: backgroundColor,
                  selectedColor: AppPalette.orange,
                  onSelected: (_) => onSelected(
                    category.id == selectedId ? null : category.id,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
