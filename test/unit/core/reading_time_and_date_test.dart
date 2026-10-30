import 'package:belog/core/utils/calculate_reading_time.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateReadingTime', () {
    test('empty and short texts never show English fallbacks', () {
      expect(calculateReadingTime(''), '约 1 分钟');
      expect(calculateReadingTime('你好'), '约 1 分钟');
      expect(
        calculateReadingTime('Less than 1 minute'),
        isNot(contains('minute')),
      );
    });

    test('minutes round and localize', () {
      final text = List.filled(650, '字').join();
      expect(calculateReadingTime(text), '约 2 分钟');
    });

    test('hours carry minutes in Chinese', () {
      final text = List.filled(20000, '字').join();
      expect(
        calculateReadingTime(text),
        matches(RegExp(r'^约 \d+ 小时( \d+ 分钟)?$')),
      );
    });
  });

  group('formatDate', () {
    test('renders a Chinese calendar date from a UTC instant', () {
      final formatted = formatDate(DateTime.utc(2026, 10, 30, 1, 30));
      expect(formatted, matches(RegExp(r'^\d{4}年\d{1,2}月\d{1,2}日$')));
      expect(formatted, contains('10月'));
    });
  });
}
