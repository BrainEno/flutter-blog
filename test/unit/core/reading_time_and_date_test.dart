import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await initializeDateFormatting('en_GB');
  });

  group('reading time', () {
    test('empty and short articles keep the one-minute minimum', () {
      expect(calculateReadingTime(zh, ''), '约 1 分钟');
      expect(calculateReadingTime(en, ''), 'About 1 minute');
      expect(calculateReadingTime(zh, '你好'), '约 1 分钟');
      expect(calculateReadingTime(en, 'one short article'), 'About 1 minute');
    });

    test('minutes are localized with English singular and plural', () {
      final oneMinute = List.filled(220, 'word').join(' ');
      final twoMinutes = List.filled(440, 'word').join(' ');
      expect(calculateReadingTime(en, oneMinute), 'About 1 minute');
      expect(calculateReadingTime(en, twoMinutes), 'About 2 minutes');
      expect(calculateReadingTime(zh, twoMinutes), '约 2 分钟');
    });

    test('rounding carries minutes into hours and handles plurals', () {
      final almostAnHour = List.filled(17880, '字').join();
      final hourAndMinute = List.filled(18300, '字').join();
      final twoHoursAndTwoMinutes = List.filled(36600, '字').join();
      expect(calculateReadingTime(en, almostAnHour), 'About 1 hour');
      expect(calculateReadingTime(zh, almostAnHour), '约 1 小时');
      expect(calculateReadingTime(en, hourAndMinute), 'About 1 hour 1 minute');
      expect(calculateReadingTime(zh, hourAndMinute), '约 1 小时 1 分钟');
      expect(
        calculateReadingTime(en, twoHoursAndTwoMinutes),
        'About 2 hours 2 minutes',
      );
    });
  });

  group('dates and numbers', () {
    test('uses locale-aware calendar formatting on a local instant', () {
      final date = DateTime(2026, 10, 30, 12);
      expect(formatDate(const Locale('zh'), date), '2026年10月30日');
      expect(formatDate(const Locale('en'), date), 'Oct 30, 2026');
      expect(formatDate(const Locale('en', 'GB'), date), '30 Oct 2026');
    });

    test('formats grouped counts in both locales', () {
      expect(formatNumber(const Locale('zh'), 1234), '1,234');
      expect(formatNumber(const Locale('en'), 1234), '1,234');
      expect(formatNumber(const Locale('en', 'IN'), 1234567), '12,34,567');
    });
  });
}
