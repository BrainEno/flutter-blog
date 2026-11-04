import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an explicit interface choice decides the content language', () {
    expect(
      contentLanguageFor(AppLanguage.zh, const Locale('en', 'US')),
      ContentLanguage.zh,
    );
    expect(
      contentLanguageFor(AppLanguage.en, const Locale('zh', 'CN')),
      ContentLanguage.en,
    );
  });

  test('follow-system reuses the interface resolution', () {
    expect(
      contentLanguageFor(AppLanguage.system, const Locale('en', 'GB')),
      ContentLanguage.en,
    );
    expect(
      contentLanguageFor(AppLanguage.system, const Locale('zh', 'HK')),
      ContentLanguage.zh,
    );
    // An unsupported device language falls back to Chinese in the interface,
    // so the content must not silently be English either.
    expect(
      contentLanguageFor(AppLanguage.system, const Locale('ja')),
      ContentLanguage.zh,
    );
  });

  test('each language maps to a locale the backend accepts', () {
    // no-wave's SUPPORTED_LOCALES is {zh-CN, zh-TW, en}.
    expect(contentLocaleTag(ContentLanguage.zh), 'zh-CN');
    expect(contentLocaleTag(ContentLanguage.en), 'en');
  });

  test('the holder only bumps its generation when the language changes', () {
    final holder = ContentLocale();
    expect(holder.language, ContentLanguage.zh);
    expect(holder.tag, 'zh-CN');
    expect(holder.generation, 0);

    holder.update(ContentLanguage.zh);
    expect(holder.generation, 0, reason: 'same language, same session');

    holder.update(ContentLanguage.en);
    expect(holder.tag, 'en');
    expect(holder.generation, 1);
  });
}
