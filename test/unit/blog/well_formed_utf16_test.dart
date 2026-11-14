import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'accepts empty, BMP, combining sequences and supplementary characters',
    () {
      for (final text in ['', 'plain', '中文', 'e\u0301', '😀', 'a😀b🦋c']) {
        expect(isWellFormedUtf16(text), isTrue, reason: text);
      }
    },
  );

  test('rejects isolated or incorrectly ordered surrogate code units', () {
    final emoji = '😀';
    final high = emoji.substring(0, 1);
    final low = emoji.substring(1);
    for (final value in [
      high,
      low,
      'a$high',
      '${low}b',
      '$low$high',
      '$high$high$low',
    ]) {
      expect(isWellFormedUtf16(value), isFalse);
    }
    expect(isWellFormedUtf16('a$high${low}b'), isTrue);
  });

  test('recognizes edge surrogate values without changing the original', () {
    final valid = String.fromCharCodes([0xd800, 0xdc00, 0xdbff, 0xdfff]);
    final wrong = String.fromCharCodes([0xd800, 0xdbff, 0xdc00]);
    expect(isWellFormedUtf16(valid), isTrue);
    expect(isWellFormedUtf16(wrong), isFalse);
    expect(valid.codeUnits, [0xd800, 0xdc00, 0xdbff, 0xdfff]);
    expect(wrong.codeUnits, [0xd800, 0xdbff, 0xdc00]);
  });
}
