import 'package:belog/features/blog/domain/editing/structured_rich_run_input.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredRichTextBuffer _buffer() => StructuredRichTextBuffer(
  blockId: 'list',
  itemIndex: 1,
  runs: [
    StructuredRichBufferRun(text: 'prefix', marks: ['bold'], href: '/guide'),
    StructuredRichBufferRun(text: '😀tail'),
    StructuredRichBufferRun(text: 'end', marks: []),
  ],
  selectionBase: -1,
  selectionExtent: -1,
  composingStart: -1,
  composingEnd: -1,
);

void main() {
  test('replaces one explicit run and translates UTF-16 IME offsets', () {
    final source = _buffer();
    final next = StructuredRichRunInput.replace(
      source: source,
      index: 1,
      text: '中😀文',
      selectionBase: 4,
      selectionExtent: 1,
      composingStart: 0,
      composingEnd: 3,
    );
    expect(source.text, 'prefix😀tailend');
    expect(next.text, 'prefix中😀文end');
    expect(next.selectionBase, 10);
    expect(next.selectionExtent, 7);
    expect(next.composingStart, 6);
    expect(next.composingEnd, 9);
    expect(next.runs.first.marks, ['bold']);
    expect(next.runs.first.href, '/guide');
    expect(next.runs[1].marks, isNull);
    expect(next.runs.last.marks, isEmpty);
    expect(next.itemIndex, 1);
    final clear = StructuredRichRunInput.clearComposition(next);
    expect(clear.text, next.text);
    expect(clear.composingStart, -1);
    expect(clear.composingEnd, -1);
    expect(clear.selectionBase, 10);
    expect(StructuredRichRunInput.hasComposition(next), isTrue);
    expect(StructuredRichRunInput.hasComposition(clear), isFalse);
  });

  test('accepts empty intermediate while preserving formatting', () {
    final next = StructuredRichRunInput.replace(
      source: _buffer(),
      index: 0,
      text: '',
      selectionBase: 0,
      selectionExtent: 0,
      composingStart: -1,
      composingEnd: -1,
    );
    expect(next.runs.first.text, isEmpty);
    expect(next.runs.first.href, '/guide');
    expect(next.runs.first.marks, ['bold']);
  });

  test('rejects invalid ranges, malformed surrogates and oversized input', () {
    final source = _buffer();
    StructuredRichTextBuffer change(
      String text,
      int base,
      int extent,
      int start,
      int end,
    ) => StructuredRichRunInput.replace(
      source: source,
      index: 0,
      text: text,
      selectionBase: base,
      selectionExtent: extent,
      composingStart: start,
      composingEnd: end,
    );
    expect(() => change('x', -1, 0, -1, -1), throwsFormatException);
    expect(() => change('x', 0, 2, -1, -1), throwsFormatException);
    expect(() => change('ab', 0, 0, 2, 1), throwsFormatException);
    expect(
      () => change(String.fromCharCode(0xd800), 0, 0, -1, -1),
      throwsFormatException,
    );
    expect(() => change('x' * 20000, 0, 0, -1, -1), throwsFormatException);
    expect(StructuredRichRunInput.canDisplay(source, 99), isFalse);
  });
}
