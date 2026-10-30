import 'package:belog/l10n/app_localizations.dart';

/// Localizes only the four built-in tag labels. Their stored values stay
/// unchanged, so existing articles and drafts retain their identifiers;
/// custom, user-authored tags are displayed verbatim.
String localizedTag(AppLocalizations l10n, String tag) => switch (tag) {
  '诗歌' => l10n.tagPoetry,
  '小说' => l10n.tagFiction,
  '原创' => l10n.tagOriginal,
  '其他' => l10n.tagOther,
  _ => tag,
};
