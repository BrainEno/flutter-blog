import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';

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
LocaleBloc systemLocaleBloc() => LocaleBloc(SystemLocalePreferenceStore());
