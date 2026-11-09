import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:flutter/material.dart';

/// The category row of the editor: a subset of the server's own catalog.
///
/// Categories are editorial structure (ADR 0016). The desk therefore never
/// invents one: it shows what `GET /categories` returned and reports the ids
/// the author picked. Tapping a selected chip removes it, because "no
/// category" is a real answer.
///
/// It picks several. An article can belong to more than one category, and an
/// editor that could only hold one would quietly drop the rest the moment the
/// author touched the row.
///
/// A row the author never touches reports nothing at all - the page then omits
/// `categoryIds` from the write, and an article whose categories were set on
/// the web keeps them.
class EditorCategorySelector extends StatelessWidget {
  const EditorCategorySelector({
    super.key,
    required this.categories,
    required this.selectedIds,
    required this.isLoading,
    required this.hasFailed,
    required this.onChanged,
    required this.onRetry,
    this.maxSelections = kMaxArticleCategories,
  });

  final List<CategoryRef> categories;

  /// The ids currently selected, in the order the author picked them.
  ///
  /// This can hold ids that are not in [categories]: the catalog is one page
  /// in one language, so an article edited from the web may carry a category
  /// this page cannot name. Those are kept - dropping an id the author never
  /// saw would be an edit nobody asked for.
  final List<String> selectedIds;

  final bool isLoading;
  final bool hasFailed;

  /// Reports the whole selection after a chip was toggled. Empty means the
  /// author cleared every category, which is a real answer.
  final ValueChanged<List<String>> onChanged;

  final VoidCallback onRetry;

  /// The bound the chips stop at; the server's own, unless a test needs a
  /// smaller one to reach it in a few taps.
  final int maxSelections;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final muted = isDarkMode ? AppPalette.mutedOnInk : AppPalette.mutedOnPaper;
    final borderColor = muted.withAlpha((0.7 * 255).toInt());
    final backgroundColor = isDarkMode
        ? AppPalette.surfaceOnInk.withAlpha((0.6 * 255).toInt())
        : AppPalette.surfaceOnPaper.withAlpha((0.4 * 255).toInt());
    final unselectedLabel = isDarkMode ? AppPalette.paper : AppPalette.ink;
    final selectable = categories
        .where((category) => category.id.isNotEmpty)
        .toList();
    final shownIds = {for (final category in selectable) category.id};
    // Unknown ids only mean something once the catalog is really here: while
    // it loads (or after it failed) every selected id looks unknown.
    final unknownCount = isLoading || hasFailed
        ? 0
        : selectedIds.where((id) => !shownIds.contains(id)).length;
    final atLimit = selectedIds.length >= maxSelections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.editorCategoryTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        Text(
          context.l10n.editorCategoryHint(maxSelections),
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
        else ...[
          Wrap(
            spacing: NoWaveSpacing.small,
            runSpacing: NoWaveSpacing.small,
            children: [
              for (final category in selectable)
                InputChip(
                  label: Text(
                    category.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: selectedIds.contains(category.id)
                          ? AppPalette.ink
                          : unselectedLabel,
                    ),
                  ),
                  selected: selectedIds.contains(category.id),
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
                  onSelected: (_) => onChanged(_toggle(category.id)),
                ),
            ],
          ),
          if (atLimit) ...[
            const SizedBox(height: NoWaveSpacing.small),
            Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.editorCategoryAtLimit(maxSelections),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ],
        // The catalog can be shorter than the article's own list - it is one
        // page in one language, and it can even be empty while the article
        // still belongs to something. Either way those ids are kept, so say so
        // instead of letting the row look like the whole story.
        if (unknownCount > 0) ...[
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            context.l10n.editorCategoryUnknown(unknownCount),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }

  /// Adds or removes one id, never exceeding the server's bound.
  ///
  /// At the bound an unselected chip simply does nothing: the row already says
  /// why (a live region, so a screen reader hears it once).
  List<String> _toggle(String id) {
    if (selectedIds.contains(id)) {
      return [
        for (final selected in selectedIds)
          if (selected != id) selected,
      ];
    }
    if (selectedIds.length >= maxSelections) return selectedIds;
    return [...selectedIds, id];
  }
}
