import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/presentation/viewer/article_outline.dart';
import 'package:flutter/material.dart';

/// The contents list: the article's headings, the section the reader is in
/// marked, each line a way there.
///
/// Set like the text-size sheet - a title, one line of help, then the
/// lines - and indented by heading depth. The section being read carries
/// the orange rule the app uses for "you are here" and is scrolled into
/// view when the list is longer than the sheet.
class ArticleOutlineSheet extends StatefulWidget {
  const ArticleOutlineSheet({
    super.key,
    required this.entries,
    required this.current,
  });

  final List<OutlineEntry> entries;

  /// The index of the section being read; null before the first heading.
  final int? current;

  /// Shows the list and completes with the index of the chosen heading, or
  /// null when the sheet is dismissed.
  static Future<int?> show(
    BuildContext context, {
    required List<OutlineEntry> entries,
    required int? current,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => ArticleOutlineSheet(entries: entries, current: current),
    );
  }

  @override
  State<ArticleOutlineSheet> createState() => _ArticleOutlineSheetState();
}

class _ArticleOutlineSheetState extends State<ArticleOutlineSheet> {
  final GlobalKey _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _currentKey.currentContext;
      if (!mounted || current == null) return;
      // Into view without a glide: the sheet is only just open.
      Scrollable.ensureVisible(current, alignment: 1 / 3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      // Never taller than most of the screen: the article stays in sight
      // above it, and a long list scrolls inside.
      constraints: BoxConstraints(maxHeight: height * 0.7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          NoWaveSpacing.page,
          NoWaveSpacing.large,
          NoWaveSpacing.page,
          NoWaveSpacing.section,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.readerOutlineTitle,
                style: NoWaveTypography.title(context),
              ),
            ),
            const SizedBox(height: NoWaveSpacing.xs),
            Text(l10n.readerOutlineHint, style: NoWaveTypography.meta(context)),
            const SizedBox(height: NoWaveSpacing.medium),
            for (final (index, entry) in widget.entries.indexed)
              _OutlineLine(
                key: index == widget.current ? _currentKey : null,
                entry: entry,
                current: index == widget.current,
                onTap: () => Navigator.of(context).pop(index),
              ),
          ],
        ),
      ),
    );
  }
}

class _OutlineLine extends StatelessWidget {
  const _OutlineLine({
    super.key,
    required this.entry,
    required this.current,
    required this.onTap,
  });

  final OutlineEntry entry;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A top heading at the size of the section heads under the article, a
    // nested one a step down and muted: the shape of the piece at a glance.
    final style =
        NoWaveTypography.title(
          context,
          size: entry.depth == 0
              ? NoWaveTypeScale.sectionTitle
              : NoWaveTypeScale.actionRow,
        ).copyWith(
          color: current || entry.depth == 0
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        );
    return Semantics(
      container: true,
      button: true,
      selected: current,
      label: entry.title,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('reader-outline-${entry.title}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: NoWaveSizes.tapTarget),
          child: Container(
            // The rule runs down the line's start edge; the other lines keep
            // the same inset so the words do not shift when it moves.
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(
                  color: current ? AppPalette.orange : Colors.transparent,
                  width: NoWaveStroke.focus,
                ),
              ),
            ),
            padding: EdgeInsetsDirectional.only(
              start: NoWaveSpacing.medium * (entry.depth + 1),
              top: NoWaveSpacing.small,
              bottom: NoWaveSpacing.small,
            ),
            alignment: AlignmentDirectional.centerStart,
            child: Text(entry.title, style: style),
          ),
        ),
      ),
    );
  }
}
