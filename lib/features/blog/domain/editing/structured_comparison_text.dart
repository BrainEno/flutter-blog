import 'package:belog/core/utils/well_formed_utf16.dart';

/// Exact single-span text comparison, using UTF-16 offsets as Flutter does.
/// This is an advisory overview, not an edit operation or semantic diff.
/// The common prefix and suffix never split a surrogate pair. It deliberately
/// does not claim to identify multiple independent edits or grapheme clusters.
final class StructuredTextChange {
  const StructuredTextChange._({
    required this.prefix,
    required this.beforeMiddle,
    required this.afterMiddle,
    required this.suffix,
  });

  /// Returns null for unrenderable strings; no transformation is attempted.
  static StructuredTextChange? between(String before, String after) {
    if (!isWellFormedUtf16(before) || !isWellFormedUtf16(after)) return null;
    var start = 0;
    final shortest = before.length < after.length
        ? before.length
        : after.length;
    while (start < shortest &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    if (_splitsPair(before, start) || _splitsPair(after, start)) start--;
    var oldEnd = before.length;
    var newEnd = after.length;
    while (oldEnd > start &&
        newEnd > start &&
        before.codeUnitAt(oldEnd - 1) == after.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    if (_splitsPair(before, oldEnd) || _splitsPair(after, newEnd)) {
      oldEnd++;
      newEnd++;
    }
    return StructuredTextChange._(
      prefix: before.substring(0, start),
      beforeMiddle: before.substring(start, oldEnd),
      afterMiddle: after.substring(start, newEnd),
      suffix: before.substring(oldEnd),
    );
  }

  final String prefix;
  final String beforeMiddle;
  final String afterMiddle;
  final String suffix;
  bool get changed => beforeMiddle.isNotEmpty || afterMiddle.isNotEmpty;
}

bool _splitsPair(String value, int offset) {
  if (offset <= 0 || offset >= value.length) return false;
  final left = value.codeUnitAt(offset - 1);
  final right = value.codeUnitAt(offset);
  return left >= 0xd800 && left <= 0xdbff && right >= 0xdc00 && right <= 0xdfff;
}

/// A display-only paging plan over exact UTF-16 code units. Every chunk is
/// independently renderable, and concatenating them reproduces the input.
/// No persisted copy, logging, URL handling, or clipboard access is involved.
final class StructuredValuePages {
  StructuredValuePages._(this._text, this._boundaries);

  static StructuredValuePages? create(String text, {int pageSize = 1000}) {
    if (pageSize < 2) throw ArgumentError.value(pageSize, 'pageSize');
    if (!isWellFormedUtf16(text)) return null;
    final boundaries = <int>[0];
    var offset = 0;
    while (offset < text.length) {
      var next = offset + pageSize;
      if (next > text.length) next = text.length;
      if (_splitsPair(text, next)) next--;
      boundaries.add(next);
      offset = next;
    }
    if (boundaries.length == 1) boundaries.add(0);
    return StructuredValuePages._(text, List.unmodifiable(boundaries));
  }

  final String _text;
  final List<int> _boundaries;
  int get length => _boundaries.length - 1;
  String page(int index) {
    if (index < 0 || index >= length) {
      throw RangeError.range(index, 0, length - 1, 'index');
    }
    return _text.substring(_boundaries[index], _boundaries[index + 1]);
  }
}
