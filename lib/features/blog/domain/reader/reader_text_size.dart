/// How large the article text is set on the reading page, smallest first.
///
/// One device-wide choice, like the theme: someone who reads with larger
/// type wants it in every article, and on every account they sign in with.
/// It sizes the text of the piece only - the app around it keeps following
/// the system text size, which this sits on top of.
enum ReaderTextSize {
  small,
  standard,
  large,
  extraLarge,
  largest;

  /// The stored name back to a size; anything unknown is [standard], so a
  /// value written by a later version never leaves the reader stuck.
  static ReaderTextSize parse(String? raw) {
    for (final size in values) {
      if (size.name == raw) return size;
    }
    return standard;
  }
}

/// Where the reader's text size is kept.
abstract interface class ReaderTextSizeStore {
  Future<ReaderTextSize> load();

  Future<void> save(ReaderTextSize size);
}
