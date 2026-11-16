import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';

/// The local input surface edits exactly one explicitly chosen run. The entire
/// string from a TextField is never diffed against the complete formatted
/// paragraph: repeated text and IME replacements make such a diff ambiguous.
/// Replacing a run preserves its marks (including null versus empty) and link,
/// every other run and their ordering. Nothing here writes or publishes.
class StructuredRichRunInput {
  const StructuredRichRunInput._();

  static bool canDisplay(StructuredRichTextBuffer buffer, int index) {
    if (index < 0 || index >= buffer.runs.length) return false;
    return isWellFormedUtf16(buffer.runs[index].text);
  }

  static bool hasComposition(StructuredRichTextBuffer buffer) =>
      buffer.composingStart >= 0 &&
      buffer.composingStart != buffer.composingEnd;

  static int runStart(StructuredRichTextBuffer buffer, int index) {
    RangeError.checkValidIndex(index, buffer.runs, 'index');
    var offset = 0;
    for (var i = 0; i < index; i++) {
      offset += buffer.runs[i].text.length;
    }
    return offset;
  }

  /// Convert an explicitly selected run's current input value to an immutable
  /// buffer. Offsets from Flutter are relative to the selected run; persisted
  /// offsets are relative to the entire target. Invalid intermediate offsets,
  /// oversized content and unrenderable UTF-16 fail closed.
  static StructuredRichTextBuffer replace({
    required StructuredRichTextBuffer source,
    required int index,
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int composingStart,
    required int composingEnd,
  }) {
    if (!canDisplay(source, index) || !isWellFormedUtf16(text)) {
      throw const FormatException('Cannot render the selected run');
    }
    final start = runStart(source, index);
    final old = source.runs[index];
    final nextLength = source.text.length - old.text.length + text.length;
    if (nextLength > 20000) throw const FormatException('Buffer too long');
    final selection = _translatePair(
      selectionBase,
      selectionExtent,
      text.length,
      start,
    );
    final composing = _translatePair(
      composingStart,
      composingEnd,
      text.length,
      start,
      ordered: true,
    );
    final runs = List<StructuredRichBufferRun>.of(source.runs);
    runs[index] = StructuredRichBufferRun(
      text: text,
      marks: old.marks,
      href: old.href,
    );
    return StructuredRichTextBuffer(
      blockId: source.blockId,
      itemIndex: source.itemIndex,
      runs: runs,
      selectionBase: selection.$1,
      selectionExtent: selection.$2,
      composingStart: composing.$1,
      composingEnd: composing.$2,
    );
  }

  /// A recovered composing range is only stored metadata, not a live IME
  /// session. Clearing it requires an explicit user decision in the UI.
  static StructuredRichTextBuffer clearComposition(
    StructuredRichTextBuffer source,
  ) => StructuredRichTextBuffer(
    blockId: source.blockId,
    itemIndex: source.itemIndex,
    runs: source.runs,
    selectionBase: source.selectionBase,
    selectionExtent: source.selectionExtent,
    composingStart: -1,
    composingEnd: -1,
  );

  static (int, int) _translatePair(
    int first,
    int second,
    int length,
    int start, {
    bool ordered = false,
  }) {
    if (first == -1 && second == -1) return (-1, -1);
    if (first < 0 ||
        second < 0 ||
        first > length ||
        second > length ||
        (ordered && first > second)) {
      throw const FormatException('Input range is outside the selected run');
    }
    return (start + first, start + second);
  }
}
