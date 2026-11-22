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

/// A short date for an inbox row, relative to [now] in local time: the
/// time of day for today ("14:30"), the weekday within the past week
/// ("周一", "Mon"), the month and day this year ("11月20日", "Nov 20"), and
/// the full date before that.
///
/// A message from twenty minutes ago printed as "2026年11月22日" said nothing
/// the reader did not know, and was long enough to be cut off beside an
/// unread count. Words such as "yesterday" are left out on purpose: they
/// need translations, and a weekday is just as quick to read.
String formatRecent(Locale locale, DateTime date, {DateTime? now}) {
  final tag = locale.toString();
  final local = date.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final todayStart = DateTime(today.year, today.month, today.day);
  final daysAgo = todayStart.difference(day).inDays;
  if (daysAgo <= 0) return DateFormat.Hm(tag).format(local);
  if (daysAgo < 7) return DateFormat.E(tag).format(local);
  if (local.year == today.year) return DateFormat.MMMd(tag).format(local);
  return DateFormat.yMMMd(tag).format(local);
}

/// Formats a count according to the resolved locale, including grouping.
String formatNumber(Locale locale, int number) =>
    NumberFormat.decimalPattern(locale.toString()).format(number);

/// Formats a share from 0 to 1 as a whole percentage in the resolved
/// locale ("42%").
String formatPercent(Locale locale, double share) =>
    NumberFormat.percentPattern(locale.toString()).format(share);
