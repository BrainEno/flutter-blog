import 'package:belog/features/blog/presentation/editor/markdown_editing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _value(String text, int base, [int? extent]) =>
    TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: base, extentOffset: extent ?? base),
    );

/// Typing Enter at [caret] in [text], as the field reports it.
TextEditingValue? _enter(String text, int caret) => continueMarkdownBlock(
  _value(text, caret),
  _value('${text.substring(0, caret)}\n${text.substring(caret)}', caret + 1),
);

void expectValue(TextEditingValue? actual, String text, int base, [int? end]) {
  expect(actual, isNotNull);
  expect(actual!.text, text);
  expect(actual.selection.start, base);
  expect(actual.selection.end, end ?? base);
}

void main() {
  group('toggleInlineMark', () {
    test('wraps the selection and keeps the words selected', () {
      final next = toggleInlineMark(
        _value('say hello', 4, 9),
        MarkdownInlineMark.bold,
      );
      expectValue(next, 'say **hello**', 6, 11);
    });

    test('a second press unwraps the same words', () {
      final next = toggleInlineMark(
        _value('say **hello**', 6, 11),
        MarkdownInlineMark.bold,
      );
      expectValue(next, 'say hello', 4, 9);
    });

    test('markers selected along with the words also unwrap', () {
      final next = toggleInlineMark(
        _value('~~gone~~', 0, 8),
        MarkdownInlineMark.strikethrough,
      );
      expectValue(next, 'gone', 0, 4);
    });

    test('a caret gets an empty pair, which a second press removes', () {
      final paired = toggleInlineMark(_value('ab', 1), MarkdownInlineMark.bold);
      expectValue(paired, 'a****b', 3);
      final removed = toggleInlineMark(paired, MarkdownInlineMark.bold);
      expectValue(removed, 'ab', 1);
    });

    test('italic inside bold nests instead of eating a bold star', () {
      final next = toggleInlineMark(
        _value('**x**', 2, 3),
        MarkdownInlineMark.italic,
      );
      expectValue(next, '***x***', 3, 4);
    });

    test('spaces at the selection edges stay outside the markers', () {
      final next = toggleInlineMark(
        _value('a word b', 1, 7),
        MarkdownInlineMark.bold,
      );
      expectValue(next, 'a **word** b', 4, 8);
    });

    test('underline uses the tag the article codec reads', () {
      final next = toggleInlineMark(
        _value('u', 0, 1),
        MarkdownInlineMark.underline,
      );
      expectValue(next, '<u>u</u>', 3, 4);
    });

    test('a field that never had focus inserts at the end', () {
      final next = toggleInlineMark(
        const TextEditingValue(text: 'ab'),
        MarkdownInlineMark.code,
      );
      expectValue(next, 'ab``', 3);
    });
  });

  group('line styles', () {
    test('the heading button walks H2, H3, H4 and back', () {
      var value = _value('Title', 2);
      value = cycleHeading(value);
      expectValue(value, '## Title', 5);
      value = cycleHeading(value);
      expectValue(value, '### Title', 6);
      value = cycleHeading(value);
      expectValue(value, '#### Title', 7);
      value = cycleHeading(value);
      expectValue(value, 'Title', 2);
    });

    test('a list covers every written line and toggles back', () {
      final listed = toggleLineStyle(
        _value('a\nb\n\nc', 0, 6),
        MarkdownLineStyle.bullet,
      );
      expectValue(listed, '- a\n- b\n\n- c', 0, 12);
      final plain = toggleLineStyle(listed, MarkdownLineStyle.bullet);
      expectValue(plain, 'a\nb\n\nc', 0, 6);
    });

    test('numbered lines count from one', () {
      final next = toggleLineStyle(
        _value('x\ny', 0, 3),
        MarkdownLineStyle.ordered,
      );
      expect(next.text, '1. x\n2. y');
    });

    test('an empty line takes the marker, ready for typing', () {
      expectValue(
        toggleLineStyle(_value('', 0), MarkdownLineStyle.quote),
        '> ',
        2,
      );
    });

    test('another style replaces the marker the line had', () {
      expectValue(
        toggleLineStyle(_value('- item', 6), MarkdownLineStyle.quote),
        '> item',
        6,
      );
      expect(lineStyleOf('### x'), MarkdownLineStyle.heading3);
      expect(lineStyleOf('12. x'), MarkdownLineStyle.ordered);
      expect(lineStyleOf('plain'), MarkdownLineStyle.paragraph);
    });

    test('only the line with the caret changes', () {
      final next = toggleLineStyle(
        _value('one\ntwo\nthree', 5),
        MarkdownLineStyle.heading2,
      );
      expectValue(next, 'one\n## two\nthree', 8);
    });
  });

  group('blocks', () {
    test('an image stands on its own with the caret at its description', () {
      final next = insertImage(_value('Hello', 5), 'https://e.com/p.png');
      expectValue(next, 'Hello\n\n![](https://e.com/p.png)\n', 9);
    });

    test('a code block wraps the selection or waits on an empty line', () {
      expectValue(insertCodeBlock(_value('x()', 0, 3)), '```\nx()\n```\n', 7);
      expectValue(insertCodeBlock(_value('', 0)), '```\n\n```\n', 4);
    });

    test('a code block fence outgrows backticks in the code', () {
      final next = insertCodeBlock(_value('```', 0, 3));
      expect(next.text, startsWith('````\n```\n````'));
    });

    test('a link wraps the selected words', () {
      expectValue(
        insertLink(_value('see docs', 4, 8), 'https://e.com'),
        'see [docs](https://e.com)',
        25,
      );
    });

    test('a link at a caret uses the given words, escaped', () {
      final next = insertLink(_value('', 0), 'https://e.com', label: 'a]b');
      expect(next.text, r'[a\]b](https://e.com)');
    });
  });

  group('Enter continues lists and quotes', () {
    test('bullets, numbers, quotes and indentation carry on', () {
      expectValue(_enter('- milk', 6), '- milk\n- ', 9);
      expectValue(_enter('3. eggs', 7), '3. eggs\n4. ', 11);
      expectValue(_enter('> said', 6), '> said\n> ', 9);
      expectValue(_enter('  * nested', 10), '  * nested\n  * ', 15);
    });

    test('Enter on an empty item ends the list', () {
      expectValue(_enter('a\n- ', 4), 'a\n', 2);
    });

    test('ordinary text, code and other edits are left alone', () {
      expect(_enter('hello', 5), isNull);
      expect(_enter('-x', 2), isNull);
      expect(_enter('1.5 apples', 10), isNull);
      expect(_enter('```\n- x', 7), isNull);
      expect(continueMarkdownBlock(_value('a', 1), _value('ab', 2)), isNull);
    });

    test('the formatter passes other edits through unchanged', () {
      const formatter = MarkdownContinuationFormatter();
      final typed = _value('ab', 2);
      expect(formatter.formatEditUpdate(_value('a', 1), typed), same(typed));
      expect(
        formatter.formatEditUpdate(_value('- a', 3), _value('- a\n', 4)).text,
        '- a\n- ',
      );
    });
  });

  test('word count: each CJK character and each Latin word', () {
    expect(countArticleWords(''), 0);
    expect(countArticleWords('你好世界'), 4);
    expect(countArticleWords('Hello brave new world'), 4);
    expect(countArticleWords('中文 and English'), 4);
    expect(countArticleWords("don't stop"), 2);
    // Addresses are not read, so they do not count.
    expect(countArticleWords('see [docs](https://example.com/a-b)'), 2);
  });
}
