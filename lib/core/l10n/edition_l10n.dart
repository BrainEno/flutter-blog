import 'package:belog/l10n/app_localizations.dart';

/// The human name of a content edition the backend reported.
///
/// The API answers with BCP-47-ish tags (`zh-CN`, `zh-TW`, `en`). They are
/// data, not interface language: they must be readable while the interface is
/// in either language, so the label comes from the localization file rather
/// than from the tag itself.
///
/// Returns null for an unknown tag (an older cache row, a locale a future
/// server adds): the caller shows no edition badge rather than guessing or
/// printing a raw code at the reader.
String? contentEditionLabel(AppLocalizations l10n, String? locale) {
  switch (locale?.trim() ?? '') {
    case 'zh-CN':
      return l10n.languageChinese;
    case 'zh-TW':
      return l10n.languageChineseTraditional;
    case 'en':
      return l10n.languageEnglish;
    default:
      return null;
  }
}
