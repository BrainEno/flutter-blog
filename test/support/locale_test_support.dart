import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:flutter/widgets.dart';

/// A store that never has a saved choice, so [systemLocaleBloc] keeps the
/// historical "follow the device" behaviour.
class SystemLocalePreferenceStore implements LocalePreferenceStore {
  @override
  Future<AppLanguage> load() async => AppLanguage.system;

  @override
  Future<void> save(AppLanguage language) async {}
}

/// The app-wide language bloc the feed listens to (issue #108).
///
/// Pages that react to a content-language change need one in the tree; tests
/// that do not switch language use this system-default one.
///
/// The device locale is pinned to Chinese so the content language stays
/// `zh-CN`, the historical default the older assertions were written against:
/// a test runner that reports `en-US` would otherwise switch the feed to
/// English the moment this bloc initializes.
LocaleBloc systemLocaleBloc() => LocaleBloc(
  SystemLocalePreferenceStore(),
  deviceLocale: () => const Locale('zh'),
);
