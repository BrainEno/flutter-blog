/// Whether a Dart string can be passed to Flutter's text renderer without
/// containing an unmatched UTF-16 surrogate. This checks representation only;
/// it does not normalize text or define grapheme boundaries.
bool isWellFormedUtf16(String text) {
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= text.length) return false;
      final next = text.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) return false;
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
