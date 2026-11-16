import 'package:belog/features/blog/domain/entities/article_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArticleRevision', () {
    test('keeps the maximum signed int64 decimal string byte-for-byte', () {
      final revision = ArticleRevision.parse('9223372036854775807');

      expect(revision?.value, '9223372036854775807');
      expect(revision.toString(), '9223372036854775807');
    });

    test('rejects noncanonical and unsafe values', () {
      for (final raw in [
        '',
        '-1',
        '+1',
        '01',
        '0001',
        ' 1',
        '1 ',
        '1.0',
        '9223372036854775808',
        42,
      ]) {
        expect(ArticleRevision.parse(raw), isNull, reason: '$raw must fail');
      }
    });
  });
}
