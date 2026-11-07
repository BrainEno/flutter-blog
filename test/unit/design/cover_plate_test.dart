import 'dart:io';

import 'package:belog/core/design/cover/no_wave_cover_plate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the default-cover layer: four plates, one stable rule, no chance
/// involved, and every asset actually shipped.
void main() {
  test('the mapping is pinned, not incidental', () {
    // If these change, every cover-less article in the app repaints. That is a
    // product decision, not a refactor, so it has to be made here on purpose.
    const expected = {
      'hello': NoWaveCoverPlate.column,
      'foobar': NoWaveCoverPlate.arc,
      '中': NoWaveCoverPlate.arc,
      'an-article': NoWaveCoverPlate.halftone,
      'my-article': NoWaveCoverPlate.arc,
      '再次回到台北': NoWaveCoverPlate.halftone,
    };
    expected.forEach((seed, plate) {
      expect(
        NoWaveCoverPlate.forSeed(seed),
        plate,
        reason: '"$seed" must keep the plate it has today',
      );
    });
  });

  test('an identity always lands on the same plate', () {
    for (final seed in ['1', 'article-9', 'a-city-and-its-seasons']) {
      expect(NoWaveCoverPlate.forSeed(seed), NoWaveCoverPlate.forSeed(seed));
    }
  });

  test('all four plates get used', () {
    // One plate that never wins is a plate that should not ship.
    final counts = <NoWaveCoverPlate, int>{};
    for (var i = 0; i < 400; i++) {
      final plate = NoWaveCoverPlate.forSeed('article-$i');
      counts[plate] = (counts[plate] ?? 0) + 1;
    }
    for (final plate in NoWaveCoverPlate.values) {
      expect(
        counts[plate] ?? 0,
        greaterThan(40),
        reason: '${plate.name} is picked too rarely to be worth its weight',
      );
    }
  });

  test('every plate is a bundled asset of real size', () {
    for (final plate in NoWaveCoverPlate.values) {
      final file = File(plate.asset);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${plate.name} points at ${plate.asset}, which is not there',
      );
      expect(
        file.lengthSync(),
        greaterThan(20 * 1024),
        reason: '${plate.asset} is too small to be a cover',
      );
      // A JPEG, so the decoder Flutter ships can read it.
      expect(file.readAsBytesSync().take(2), [0xFF, 0xD8]);
    }
  });

  test('the asset directory is declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final plate in NoWaveCoverPlate.values) {
      final dir = plate.asset.substring(0, plate.asset.lastIndexOf('/') + 1);
      expect(
        pubspec.contains('- $dir'),
        isTrue,
        reason: 'pubspec.yaml does not list $dir, so the asset is not bundled',
      );
    }
  });

  test('nothing about a cover is random or per-process', () {
    // The doc comments explain why hashCode and Random are wrong; the code must
    // not use them. Comments are dropped before the scan, so the explanation
    // stays allowed.
    const files = [
      'lib/core/design/cover/no_wave_cover_plate.dart',
      'lib/core/utils/stable_hash.dart',
      'lib/features/blog/presentation/widgets/article_cover.dart',
    ];
    for (final path in files) {
      final code = File(path)
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final forbidden in ['hashCode', 'Random', 'DateTime.now']) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: '$path must not use $forbidden to choose a cover',
        );
      }
    }
  });
}
