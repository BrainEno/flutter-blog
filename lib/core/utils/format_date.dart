import 'package:belog/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Formats an instant in the user's local time zone and UI locale.
///
/// Material's localization delegate initializes intl's date symbols before
/// widgets are built. Unit tests outside a localized app must call
/// `initializeDateFormatting` before using this helper.
String formatDate(AppLocalizations l10n, DateTime date) =>
    DateFormat.yMMMd(l10n.localeName).format(date.toLocal());

/// Formats a count according to the active UI locale, including grouping.
String formatNumber(AppLocalizations l10n, int number) =>
    NumberFormat.decimalPattern(l10n.localeName).format(number);
