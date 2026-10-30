import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// Shorthand for [AppLocalizations.of].
///
/// The generated [AppLocalizations.of] is non-null (l10n.yaml sets
/// `nullable-getter: false`), so missing delegates fail loudly.
extension ContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Resolve the first supported device language while retaining English region
/// subtags for date, number and Material widget formatting. All Chinese
/// variants use Simplified Chinese, the only Chinese catalog we ship.
/// Unsupported language lists fall back to Simplified Chinese.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final locale in preferred ?? const <Locale>[]) {
    if (locale.languageCode == 'en') return locale;
    if (locale.languageCode == 'zh') return const Locale('zh', 'CN');
  }
  return const Locale('zh', 'CN');
}
