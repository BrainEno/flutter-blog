import 'dart:ui' show Locale;

import 'package:intl/intl.dart';

/// Formats an instant in local time using the resolved locale, including its
/// region (for example en_GB versus en_US).
///
/// Material's localization delegate initializes intl's date symbols before
/// widgets are built. Unit tests outside a localized app must call
/// `initializeDateFormatting` before using this helper.
String formatDate(Locale locale, DateTime date) =>
    DateFormat.yMMMd(locale.toString()).format(date.toLocal());

/// Formats a count according to the resolved locale, including grouping.
String formatNumber(Locale locale, int number) =>
    NumberFormat.decimalPattern(locale.toString()).format(number);
