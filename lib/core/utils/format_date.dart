import 'dart:ui' show Locale;

import 'package:intl/intl.dart';

/// Formats an instant in local time using the resolved locale, including its
/// region (for example en_GB versus en_US).
///
/// [withTime] appends the locale's hours, minutes and seconds. Lists of
/// articles, comments and notifications show the calendar date only; a
/// security surface such as the signed-in sessions list needs the time of
/// day to tell two sign-ins on the same date apart (#303). This is the only
/// place that builds a `DateFormat`, so every screen agrees on the shape.
///
/// Material's localization delegate initializes intl's date symbols before
/// widgets are built. Unit tests outside a localized app must call
/// `initializeDateFormatting` before using this helper.
String formatDate(Locale locale, DateTime date, {bool withTime = false}) {
  final format = DateFormat.yMMMd(locale.toString());
  if (withTime) format.add_jms();
  return format.format(date.toLocal());
}

/// The locale's abbreviated weekday of [date] in local time ("Mon", "周一").
///
/// Used where a row of days needs short labels, such as the reading
/// activity chart; still the one place that builds a `DateFormat`.
String formatWeekdayShort(Locale locale, DateTime date) =>
    DateFormat.E(locale.toString()).format(date.toLocal());

/// The locale's month, day and weekday of [date] in local time, without the
/// year ("Thu, Nov 19", "11月19日周四"): a dateline, read as "today".
String formatDateline(Locale locale, DateTime date) =>
    DateFormat.MMMEd(locale.toString()).format(date.toLocal());

/// Formats a count according to the resolved locale, including grouping.
String formatNumber(Locale locale, int number) =>
    NumberFormat.decimalPattern(locale.toString()).format(number);
