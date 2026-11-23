import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/viewer/reading_marks.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

/// How far a reader got, in words: "42% read", "Finished", or null when
/// there is nothing to say (never opened, or barely begun). The history page
/// and the article lists use the same words.
String? readingMarkLabel(
  AppLocalizations l10n,
  Locale locale,
  double? progress,
) => switch (ReadingProgress.stageOf(progress)) {
  ReadingStage.unstarted => null,
  ReadingStage.partway => l10n.historyProgress(
    formatPercent(locale, progress!),
  ),
  ReadingStage.finished => l10n.historyFinished,
};

/// Builds with the signed-in reader's mark for [blogId] - null when there
/// is none - and again whenever it changes.
///
/// The marks come from the app's [ReadingMarks] (or [marks], for a test).
/// Where none is registered, as in a widget test of a single list, the
/// label is always null and nothing listens.
class ReadingMarkBuilder extends StatelessWidget {
  const ReadingMarkBuilder({
    super.key,
    required this.blogId,
    required this.builder,
    this.marks,
  });

  final String blogId;
  final Widget Function(BuildContext context, String? label) builder;
  final ReadingMarks? marks;

  @override
  Widget build(BuildContext context) {
    final locator = GetIt.instance;
    final source =
        marks ??
        (locator.isRegistered<ReadingMarks>() ? locator<ReadingMarks>() : null);
    if (source == null) return builder(context, null);
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) => builder(
        context,
        readingMarkLabel(
          context.l10n,
          Localizations.localeOf(context),
          source.progressFor(blogId),
        ),
      ),
    );
  }
}
