import 'package:belog/features/blog/presentation/editor/markdown_text_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = TextStyle(color: Color(0xFF000000));
const _faded = TextStyle(color: Color(0xFF888888));
const _accent = TextStyle(color: Color(0xFFFF6600));
const _styles = MarkdownHighlightStyles(
  base: _base,
  faded: _faded,
  accent: _accent,
);

TextSpan _span(List<TextSpan> spans, String text) =>
    spans.firstWhere((span) => span.text == text);

void main() {
  const sample =
      '## Head\n'
      '\n'
      'Say **bold** and *it*, `code`, ~~x~~, <u>u</u>, [l](https://e.com)\n'
      '- item\n'
      '> q\n'
      '```\n'
      '**not bold**\n'
      '```\n'
      '![a](https://e.com/i.png)\n'
      r'\*esc';

  test('the spans spell the text exactly, character for character', () {
    final spans = highlightMarkdown(sample, _styles);
    expect(spans.map((span) => span.text).join(), sample);
  });

  test('headings and emphasis show, while their signs fade', () {
    final spans = highlightMarkdown(sample, _styles);
    expect(_span(spans, '## ').style?.color, _faded.color);
    expect(_span(spans, 'Head').style?.fontWeight, FontWeight.w700);
    expect(_span(spans, 'bold').style?.fontWeight, FontWeight.w700);
    expect(_span(spans, '**').style?.color, _faded.color);
    expect(_span(spans, 'it').style?.fontStyle, FontStyle.italic);
    expect(_span(spans, 'x').style?.decoration, TextDecoration.lineThrough);
    expect(_span(spans, 'u').style?.decoration, TextDecoration.underline);
    expect(_span(spans, 'l').style?.color, _accent.color);
    expect(_span(spans, 'code').style?.color, _accent.color);
  });

  test('list and quote markers carry the accent', () {
    final spans = highlightMarkdown(sample, _styles);
    expect(_span(spans, '- ').style?.color, _accent.color);
    expect(_span(spans, '> ').style?.color, _accent.color);
    expect(_span(spans, 'q').style?.fontStyle, FontStyle.italic);
  });

  test('code blocks and image lines are quiet and never formatted', () {
    final spans = highlightMarkdown(sample, _styles);
    final code = _span(spans, '**not bold**');
    expect(code.style?.color, _faded.color);
    expect(code.style?.fontWeight, isNot(FontWeight.w700));
    expect(
      _span(spans, '![a](https://e.com/i.png)').style?.color,
      _faded.color,
    );
  });

  test('an escaped sign stays a plain character', () {
    final spans = highlightMarkdown(r'\*esc', _styles);
    expect(spans.map((span) => span.text), [r'\', '*', 'esc']);
    expect(spans.first.style?.color, _faded.color);
  });

  test('the text being composed by an input method is underlined', () {
    final spans = highlightMarkdown(
      'abc',
      _styles,
      composing: const TextRange(start: 1, end: 2),
    );
    expect(spans.map((span) => span.text), ['a', 'b', 'c']);
    expect(spans[1].style?.decoration, TextDecoration.underline);
    expect(spans[0].style?.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('the controller paints the field and keeps plain text', (
    tester,
  ) async {
    final controller = MarkdownTextController(text: '**b**');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      style: _base,
      withComposing: false,
    );
    final children = span.children!.cast<TextSpan>();
    expect(children.map((child) => child.text).join(), '**b**');
    expect(children, hasLength(3));
    expect(controller.text, '**b**');
  });
}
