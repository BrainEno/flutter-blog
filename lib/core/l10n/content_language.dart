import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/widgets.dart';

/// The language article content is requested in (issue #108).
///
/// no-wave accepts `zh-CN`, `zh-TW` and `en`; the app offers Chinese and
/// English and falls back to Chinese for any other interface language, which
/// matches [resolveAppLocale].
enum ContentLanguage { zh, en }

/// The `locale` query parameter that requests [language].
String contentLocaleTag(ContentLanguage language) {
  switch (language) {
    case ContentLanguage.zh:
      return 'zh-CN';
    case ContentLanguage.en:
      return 'en';
  }
}

/// The content language implied by an interface language.
///
/// An explicit choice decides. "Follow system" reuses the interface
/// resolution, so an English device asks for English content as well instead
/// of showing English chrome around Chinese articles.
ContentLanguage contentLanguageFor(AppLanguage language, Locale deviceLocale) {
  switch (language) {
    case AppLanguage.zh:
      return ContentLanguage.zh;
    case AppLanguage.en:
      return ContentLanguage.en;
    case AppLanguage.system:
      final ui = resolveAppLocale(
        [deviceLocale],
        const [Locale('zh'), Locale('en')],
      );
      return ui.languageCode == 'en' ? ContentLanguage.en : ContentLanguage.zh;
  }
}
