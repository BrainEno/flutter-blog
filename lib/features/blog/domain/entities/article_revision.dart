/// Exact server-side article work revision used for conditional updates.
///
/// no-wave deliberately sends this as a decimal string: JavaScript and Dart
/// `double` values cannot represent every signed 64-bit integer exactly. This
/// value object therefore never exposes an integer conversion. Callers either
/// preserve [value] verbatim in storage or place it unchanged in a request's
/// `expectedRevision` field.
class ArticleRevision {
  const ArticleRevision._(this.value);

  /// The canonical non-negative decimal representation accepted by no-wave.
  final String value;

  static final BigInt _maximum = BigInt.parse('9223372036854775807');
  static final RegExp _syntax = RegExp(r'^(0|[1-9]\d{0,18})$');

  /// Accepts only the exact bigint-string contract from no-wave.
  ///
  /// A missing revision is expected from older deployments. A malformed value
  /// is deliberately treated the same at this boundary: authoring must refuse
  /// an unfenced update instead of guessing a number or rounding it.
  static ArticleRevision? parse(Object? raw) {
    if (raw is! String || !_syntax.hasMatch(raw)) return null;
    try {
      if (BigInt.parse(raw) > _maximum) return null;
    } on FormatException {
      return null;
    }
    return ArticleRevision._(raw);
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleRevision && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
