import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// The fixed tag vocabulary the editor offers.
///
/// These strings are canonical backend tags, not UI copy: the server stores
/// them as-is, so they stay stable and only their labels are localized
/// ([localizedTag]).
const List<String> editorTagOptions = ['诗歌', '小说', '原创', '其他'];

/// The tag chips below the cover slot.
class EditorTagSelector extends StatelessWidget {
  const EditorTagSelector({
    super.key,
    required this.selectedTags,
    required this.onChanged,
  });

  final List<String> selectedTags;

  /// Reports the next selection; the caller owns the list.
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkMode
        ? AppPalette.mutedOnInk.withAlpha((0.7 * 255).toInt())
        : AppPalette.mutedOnPaper.withAlpha((0.7 * 255).toInt());
    final backgroundColor = isDarkMode
        ? AppPalette.surfaceOnInk.withAlpha((0.6 * 255).toInt())
        : AppPalette.surfaceOnPaper.withAlpha((0.4 * 255).toInt());
    final unselectedLabel = isDarkMode ? AppPalette.paper : AppPalette.ink;
    return Wrap(
      spacing: 10.0,
      runSpacing: 10.0,
      children: [
        for (final tag in editorTagOptions)
          InputChip(
            label: Text(
              localizedTag(context.l10n, tag),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: selectedTags.contains(tag)
                    ? AppPalette.ink
                    : unselectedLabel,
              ),
            ),
            selected: selectedTags.contains(tag),
            elevation: 0,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(
              vertical: NoWaveSpacing.small,
              horizontal: 12.0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: borderColor),
            ),
            backgroundColor: backgroundColor,
            selectedColor: AppPalette.orange,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w500,
              color: selectedTags.contains(tag) ? AppPalette.ink : null,
            ),
            onSelected: (selected) => onChanged(_toggled(tag, selected)),
          ),
      ],
    );
  }

  List<String> _toggled(String tag, bool selected) {
    final next = List<String>.of(selectedTags);
    if (selected) {
      next.add(tag);
    } else {
      next.remove(tag);
    }
    return next;
  }
}
