import 'package:belog/core/utils/stable_hash.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the hash to the published FNV-1a 32-bit vectors, because every cover
/// in the app is downstream of it: a "cleanup" that only looks equivalent would
/// repaint every article, on every device, silently.
void main() {
  test('matches the published FNV-1a vectors', () {
    const vectors = {
      '': 0x811C9DC5,
      'a': 0xE40C292C,
      'foobar': 0xBF9CF968,
      'hello': 0x4F9F2CAB,
    };
    for (final entry in vectors.entries) {
      expect(
        stableHash32(entry.key),
        entry.value,
        reason: 'FNV-1a 32 of "${entry.key}"',
      );
    }
  });

  test('hashes UTF-8 bytes, not UTF-16 code units', () {
    // 中 is U+4E2D: one code unit, three UTF-8 bytes. Hashing code units would
    // feed a value above 255 into the xor and produce a different number.
    expect(stableHash32('中'), 0xB846D3F4);
    expect(stableHash32('文章'), 0x66749BE0);
    expect(stableHash32('再次回到台北'), 0x714370D1);
  });

  test('is a pure function of the string', () {
    expect(stableHash32('an-article'), stableHash32('an-article'));
    expect(stableHash32('hello'), 1335831723);
    expect(
      stableHash32('an-article'),
      isNot(stableHash32('another-article')),
    );
  });

  test('stays inside 32 bits whatever the length', () {
    for (final seed in ['', 'a', '中', 'x' * 500]) {
      expect(stableHash32(seed), greaterThanOrEqualTo(0));
      expect(stableHash32(seed), lessThanOrEqualTo(0xFFFFFFFF));
    }
  });
}
