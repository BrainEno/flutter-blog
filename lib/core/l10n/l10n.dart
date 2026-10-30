import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// Shorthand for [AppLocalizations.of].
///
/// The generated [AppLocalizations.of] is non-null (l10n.yaml sets
/// `nullable-getter: false`), so `context.l10n` either resolves or throws
/// loudly - usually meaning a widget was pumped without the app's
/// localization delegates (see [localizedTestApp] in test/helpers).
extension ContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
