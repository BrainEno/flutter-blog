import 'package:belog/features/blog/domain/entities/reading_stats.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A history row last read at [readAt]; the rest of the snapshot is filler.
ReadingHistoryEntry _readAt(DateTime readAt, [String id = '']) =>
    ReadingHistoryEntry(
      blogId: id.isEmpty ? readAt.toIso8601String() : id,
      title: 't',
      posterName: '',
      imageUrl: '',
      readAt: readAt,
    );

void main() {
  // A Thursday afternoon, local time.
  final now = DateTime(2026, 11, 19, 15, 30);
  DateTime daysAgo(int days, [int hour = 10]) =>
      DateTime(now.year, now.month, now.day - days, hour);

  test('an empty history has no figures and an all-zero window', () {
    final stats = ReadingStats.from(const [], now: now);
    expect(stats.isEmpty, isTrue);
    expect(stats.totalArticles, 0);
    expect(stats.articlesInWindow, 0);
    expect(stats.activeDays, 0);
    expect(stats.currentStreakDays, 0);
    expect(stats.longestStreakDays, 0);
    expect(stats.window, hasLength(ReadingStats.windowDays));
    expect(stats.window.every((day) => day.count == 0), isTrue);
    expect(stats.windowPeak, 1, reason: 'never divide the chart by zero');
  });

  test('the window runs oldest first and ends today', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(0)),
      _readAt(daysAgo(0, 8)),
      _readAt(daysAgo(2)),
      _readAt(daysAgo(6)),
      _readAt(daysAgo(7)), // one day outside the window
    ], now: now);
    expect(stats.window.first.day, DateTime(2026, 11, 13));
    expect(stats.window.last.day, DateTime(2026, 11, 19));
    expect([for (final day in stats.window) day.count], [1, 0, 0, 0, 1, 0, 2]);
    expect(stats.articlesInWindow, 4);
    expect(stats.totalArticles, 5);
    expect(stats.activeDays, 4);
    expect(stats.windowPeak, 2);
  });

  test('a streak that includes today counts back to its first day', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(0)),
      _readAt(daysAgo(1)),
      _readAt(daysAgo(2)),
      _readAt(daysAgo(4)),
    ], now: now);
    expect(stats.currentStreakDays, 3);
    expect(stats.longestStreakDays, 3);
  });

  test('a streak is not broken before the reader has read today', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(1)),
      _readAt(daysAgo(2)),
    ], now: now);
    expect(stats.currentStreakDays, 2);
  });

  test('a gap of a full day ends the current streak', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(2)),
      _readAt(daysAgo(3)),
      _readAt(daysAgo(4)),
    ], now: now);
    expect(stats.currentStreakDays, 0);
    expect(stats.longestStreakDays, 3);
  });

  test('the longest streak can lie in the past', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(0)),
      for (var d = 10; d < 15; d++) _readAt(daysAgo(d)),
    ], now: now);
    expect(stats.currentStreakDays, 1);
    expect(stats.longestStreakDays, 5);
  });

  test('several reads on one day count once toward a streak', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(0, 1)),
      _readAt(daysAgo(0, 12)),
      _readAt(daysAgo(0, 23)),
    ], now: now);
    expect(stats.currentStreakDays, 1);
    expect(stats.longestStreakDays, 1);
    expect(stats.activeDays, 1);
    expect(stats.window.last.count, 3);
  });

  test('streaks cross month and year boundaries', () {
    final newYear = DateTime(2027, 1, 1, 9);
    final stats = ReadingStats.from([
      _readAt(DateTime(2027, 1, 1, 8)),
      _readAt(DateTime(2026, 12, 31, 22)),
      _readAt(DateTime(2026, 12, 30, 7)),
    ], now: newYear);
    expect(stats.currentStreakDays, 3);
    expect(stats.window.first.day, DateTime(2026, 12, 26));
  });

  test('a future-stamped entry never extends the window or a streak', () {
    final stats = ReadingStats.from([
      _readAt(daysAgo(-1)), // tomorrow: the device clock was ahead
      _readAt(daysAgo(0)),
    ], now: now);
    expect(stats.totalArticles, 2);
    expect(stats.articlesInWindow, 1);
    expect(stats.currentStreakDays, 1);
    expect(stats.longestStreakDays, 1);
  });

  test('UTC timestamps are bucketed by the local calendar day', () {
    final local = DateTime(2026, 11, 19, 12);
    final stats = ReadingStats.from([_readAt(local.toUtc())], now: now);
    expect(stats.window.last.count, 1);
  });

  test('the window cannot be modified by a caller', () {
    final stats = ReadingStats.from([_readAt(daysAgo(0))], now: now);
    expect(
      () => stats.window.add(ReadingDay(day: now, count: 1)),
      throwsUnsupportedError,
    );
  });

  test('ReadingDay compares by value', () {
    final day = DateTime(2026, 11, 19);
    expect(ReadingDay(day: day, count: 2), ReadingDay(day: day, count: 2));
    expect(
      ReadingDay(day: day, count: 2).hashCode,
      ReadingDay(day: day, count: 2).hashCode,
    );
    expect(
      ReadingDay(day: day, count: 2),
      isNot(ReadingDay(day: day, count: 3)),
    );
    expect(ReadingDay(day: day, count: 2).toString(), contains('2026-11-19'));
  });
}
