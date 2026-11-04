import 'package:belog/core/l10n/content_language.dart';

/// The content language new requests use: written by the language bloc, read
/// by the data sources and the offline cache (issue #108).
///
/// [generation] lets a paging session notice that the language changed while a
/// request was in flight, so the page it returns is dropped instead of being
/// appended to a list rendered in another language.
class ContentLocale {
  /// The instance used when a collaborator is built without one.
  ///
  /// Production registers this singleton in the service locator and passes it
  /// explicitly; the fallback keeps tests and tools that never switch language
  /// working with the historical Chinese default.
  static final ContentLocale instance = ContentLocale();

  ContentLanguage _language = ContentLanguage.zh;
  int _generation = 0;

  ContentLanguage get language => _language;

  /// The `locale` query parameter for the current language.
  String get tag => contentLocaleTag(_language);

  /// Increments once per change; equal generations mean the same language.
  int get generation => _generation;

  void update(ContentLanguage language) {
    if (language == _language) return;
    _language = language;
    _generation++;
  }
}
