import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single-span comparison reconstructs both strings exactly', () {
    for (final pair in [
      ('abc', 'abc'),
      ('abc', 'aXc'),
      ('abc', 'aXbc'),
      ('aXbc', 'abc'),
      ('', 'new'),
      ('old', ''),
      ('A😀Z', 'A😁Z'),
      ('A😀Z', 'A🀀Z'),
      ('one two three', 'ONE two THREE'),
    ]) {
      final c = StructuredTextChange.between(pair.$1, pair.$2)!;
      expect(c.prefix + c.beforeMiddle + c.suffix, pair.$1);
      expect(c.prefix + c.afterMiddle + c.suffix, pair.$2);
      expect(c.changed, pair.$1 != pair.$2);
      for (final part in [c.prefix, c.beforeMiddle, c.afterMiddle, c.suffix]) {
        expect(isWellFormedUtf16(part), isTrue);
      }
    }
  });
  test('invalid UTF-16 is not given to the renderer', () {
    final broken = String.fromCharCode(0xd800);
    expect(StructuredTextChange.between('ok', broken), isNull);
    expect(StructuredValuePages.create(broken), isNull);
  });
  test('pages preserve all units and do not split surrogate pairs', () {
    final value = 'A😀B🀀C';
    final pages = StructuredValuePages.create(value, pageSize: 2)!;
    final chunks = [for (var i = 0; i < pages.length; i++) pages.page(i)];
    expect(chunks.join(), value);
    expect(chunks.every(isWellFormedUtf16), isTrue);
    expect(() => pages.page(-1), throwsRangeError);
    expect(() => pages.page(pages.length), throwsRangeError);
    expect(
      () => StructuredValuePages.create(value, pageSize: 1),
      throwsArgumentError,
    );
    expect(StructuredValuePages.create('')!.page(0), '');
  });
}
