import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';

/// One calendar day of reading activity, in the device's local time.
class ReadingDay {
  /// Midnight (local) of the day this entry describes.
  final DateTime day;

  /// How many history entries were last read on [day].
  final int count;

  const ReadingDay({required this.day, required this.count});

  @override
  bool operator ==(Object other) =>
      other is ReadingDay && other.day == day && other.count == count;

  @override
  int get hashCode => Object.hash(day, count);

  @override
  String toString() => 'ReadingDay(${day.toIso8601String()}, $count)';
}

/// A summary of the device-local reading history, shown above the list.
///
/// Everything is derived from the [ReadingHistoryEntry] rows the page already
/// holds: nothing new is stored or sent anywhere. The history keeps one row per
/// article and moves it on a re-read, so every figure counts *articles by the
/// day they were last read*, not individual reading sessions - re-reading an
/// old article today moves it from its old day to today. The labels on the
/// card say so.
///
/// Days are local calendar days. Day arithmetic goes through the
/// `DateTime(year, month, day ± n)` constructor rather than adding 24-hour
/// durations, so a daylight-saving change never splits or merges a day.
class ReadingStats {
  /// How many days the activity chart covers, ending today.
  static const int windowDays = 7;

  /// Every entry in the history, whenever it was read.
  final int totalArticles;

  /// Entries last read within the [windowDays] days ending today.
  final int articlesInWindow;

  /// Distinct days with at least one read.
  final int activeDays;

  /// Consecutive days with a read, ending today - or yesterday, so a streak
  /// is not reported as broken before the reader has had a chance to read
  /// today. Zero when neither day has a read.
  final int currentStreakDays;

  /// The longest run of consecutive reading days in the history.
  final int longestStreakDays;

  /// One entry per day of the window, oldest first; the last one is today.
  final List<ReadingDay> window;

  const ReadingStats({
    required this.totalArticles,
    required this.articlesInWindow,
    required this.activeDays,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.window,
  });

  /// No history at all.
  bool get isEmpty => totalArticles == 0;

  /// The busiest day count of the window, for scaling the chart; at least 1
  /// so an empty window never divides by zero.
  int get windowPeak {
    var peak = 1;
    for (final day in window) {
      if (day.count > peak) peak = day.count;
    }
    return peak;
  }

  /// Builds the summary of [entries] as seen at [now].
  ///
  /// An entry stamped later than today (a device clock that was ahead when it
  /// was recorded) still counts toward [totalArticles] and [activeDays], but
  /// never toward the window or a streak: the future has not happened yet.
  factory ReadingStats.from(
    Iterable<ReadingHistoryEntry> entries, {
    required DateTime now,
  }) {
    final today = _dayOf(now);
    final perDay = <DateTime, int>{};
    var total = 0;
    for (final entry in entries) {
      total++;
      final day = _dayOf(entry.readAt);
      perDay[day] = (perDay[day] ?? 0) + 1;
    }

    final window = <ReadingDay>[];
    for (var offset = windowDays - 1; offset >= 0; offset--) {
      final day = _shift(today, -offset);
      window.add(ReadingDay(day: day, count: perDay[day] ?? 0));
    }
    final inWindow = window.fold<int>(0, (sum, day) => sum + day.count);

    return ReadingStats(
      totalArticles: total,
      articlesInWindow: inWindow,
      activeDays: perDay.length,
      currentStreakDays: _currentStreak(perDay.keys.toSet(), today),
      longestStreakDays: _longestStreak(
        perDay.keys.where((day) => !day.isAfter(today)),
      ),
      window: List.unmodifiable(window),
    );
  }

  /// Local midnight of [instant].
  static DateTime _dayOf(DateTime instant) {
    final local = instant.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// The calendar day [days] away from [day]; negative goes back.
  static DateTime _shift(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  static int _currentStreak(Set<DateTime> days, DateTime today) {
    var cursor = today;
    if (!days.contains(cursor)) {
      cursor = _shift(today, -1);
      if (!days.contains(cursor)) return 0;
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = _shift(cursor, -1);
    }
    return streak;
  }

  static int _longestStreak(Iterable<DateTime> days) {
    final sorted = days.toList()..sort();
    var longest = 0;
    var run = 0;
    DateTime? previous;
    for (final day in sorted) {
      run = previous != null && _shift(previous, 1) == day ? run + 1 : 1;
      if (run > longest) longest = run;
      previous = day;
    }
    return longest;
  }
}
