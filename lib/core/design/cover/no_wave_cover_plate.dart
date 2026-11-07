import 'package:belog/core/utils/stable_hash.dart';

/// The four editorial plates that stand in for a missing cover.
///
/// An article without a cover used to fall back to one fixed image, so a feed
/// of eight cover-less articles looked like the same article eight times. The
/// plates are one family - ink, halftone, a single orange accent - with four
/// compositions, which is enough for a reader to tell two cards apart without
/// the app pretending the images mean something.
///
/// Which plate an article gets is decided by its *identity*, not by chance:
/// see [forSeed]. The rule is stable across launches, devices and releases,
/// which is what keeps a saved article recognisable on the screen it lands on
/// next.
enum NoWaveCoverPlate {
  /// One sumi stroke with an orange bleed underneath it.
  arc('assets/images/no_wave_cover_arc.jpg'),

  /// A halftone field ruled by a single orange hairline.
  halftone('assets/images/no_wave_cover_halftone.jpg'),

  /// Overlapping oxblood and ink blocks on a torn sheet.
  block('assets/images/no_wave_cover_block.jpg'),

  /// Vertical ink columns crossed by one orange slash.
  column('assets/images/no_wave_cover_column.jpg');

  const NoWaveCoverPlate(this.asset);

  /// Bundled 960x600 JPEG, 16:10 - the ratio of the reader header.
  final String asset;

  /// The plate for a stable identity: an article's slug or id.
  ///
  /// Never pass the title - retitling an article would repaint its cover.
  /// Never pass `hashCode` or a random value for the same reason: the plate
  /// must survive a reinstall, a second device and a Dart upgrade, and only a
  /// documented hash of the identity does that.
  static NoWaveCoverPlate forSeed(String seed) =>
      values[stableHash32(seed) % values.length];
}
