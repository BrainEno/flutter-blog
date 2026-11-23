import 'package:flutter/services.dart';

/// Pure text operations behind the editor's format toolbar and its Enter key.
///
/// Every function takes the field's current [TextEditingValue] and answers the
/// next one, so the toolbar, the input formatter and the tests share one
/// implementation. The Markdown written here is exactly the dialect
/// `article_markdown.dart` reads back into no-wave blocks.

/// An inline mark the toolbar can wrap around the selection.
enum MarkdownInlineMark { bold, italic, strikethrough, underline, code }

/// A line-level style the toolbar can apply to the lines of the selection.
///
/// [paragraph] removes whatever line marker the lines carry.
enum MarkdownLineStyle {
  paragraph,
  heading2,
  heading3,
  heading4,
  quote,
  bullet,
  ordered,
}

(String, String) _markers(MarkdownInlineMark mark) => switch (mark) {
  MarkdownInlineMark.bold => ('**', '**'),
  MarkdownInlineMark.italic => ('*', '*'),
  MarkdownInlineMark.strikethrough => ('~~', '~~'),
  MarkdownInlineMark.underline => ('<u>', '</u>'),
  MarkdownInlineMark.code => ('`', '`'),
};

/// The selection, or a caret at the end when the field never had focus.
TextSelection _selectionOf(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid) {
    return TextSelection.collapsed(offset: value.text.length);
  }
  final length = value.text.length;
  final start = selection.start.clamp(0, length);
  final end = selection.end.clamp(0, length);
  return TextSelection(baseOffset: start, extentOffset: end);
}

/// Whether [text] ends with [marker] as that mark, not as part of a longer
/// run: `**` is bold, so a single `*` in front of it is not italic.
bool _endsWithMarker(String text, String marker, MarkdownInlineMark mark) {
  if (!text.endsWith(marker)) return false;
  if (mark != MarkdownInlineMark.italic) return true;
  return !text.endsWith('**') || text.endsWith('***');
}

bool _startsWithMarker(String text, String marker, MarkdownInlineMark mark) {
  if (!text.startsWith(marker)) return false;
  if (mark != MarkdownInlineMark.italic) return true;
  return !text.startsWith('**') || text.startsWith('***');
}

/// Wraps the selection in [mark], or removes it when the selection is already
/// wrapped. A bare caret gets an empty pair with the caret inside, and a
/// second press on that empty pair takes it away again.
///
/// Spaces at the edges of the selection stay outside the markers: `** a**`
/// is not emphasis in Markdown, and the article codec trims them the same way.
TextEditingValue toggleInlineMark(
  TextEditingValue value,
  MarkdownInlineMark mark,
) {
  final (open, close) = _markers(mark);
  final text = value.text;
  final selection = _selectionOf(value);
  var start = selection.start;
  var end = selection.end;
  while (start < end && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  final before = text.substring(0, start);
  final selected = text.substring(start, end);
  final after = text.substring(end);

  // Markers just outside the selection: unwrap.
  if (_endsWithMarker(before, open, mark) &&
      _startsWithMarker(after, close, mark)) {
    final head = before.substring(0, before.length - open.length);
    return TextEditingValue(
      text: head + selected + after.substring(close.length),
      selection: TextSelection(
        baseOffset: head.length,
        extentOffset: head.length + selected.length,
      ),
    );
  }
  // Markers just inside the selection: unwrap.
  if (selected.length >= open.length + close.length &&
      _startsWithMarker(selected, open, mark) &&
      _endsWithMarker(selected, close, mark)) {
    final inner = selected.substring(
      open.length,
      selected.length - close.length,
    );
    return TextEditingValue(
      text: before + inner + after,
      selection: TextSelection(
        baseOffset: before.length,
        extentOffset: before.length + inner.length,
      ),
    );
  }
  return TextEditingValue(
    text: before + open + selected + close + after,
    selection: selected.isEmpty
        ? TextSelection.collapsed(offset: before.length + open.length)
        : TextSelection(
            baseOffset: before.length + open.length,
            extentOffset: before.length + open.length + selected.length,
          ),
  );
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

final _linePrefix = RegExp(
  r'^[ \t]*(?:#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+|\d{1,9}[.)][ \t]+)',
);
final _headingPrefix = RegExp(r'^[ \t]*(#{1,6})[ \t]+');
final _quotePrefix = RegExp(r'^[ \t]*>');
final _bulletPrefix = RegExp(r'^[ \t]*[-*+][ \t]+');
final _orderedPrefix = RegExp(r'^[ \t]*\d{1,9}[.)][ \t]+');

/// The style the line already carries.
MarkdownLineStyle lineStyleOf(String line) {
  final heading = _headingPrefix.firstMatch(line);
  if (heading != null) {
    return switch (heading.group(1)!.length) {
      3 => MarkdownLineStyle.heading3,
      4 || 5 || 6 => MarkdownLineStyle.heading4,
      _ => MarkdownLineStyle.heading2,
    };
  }
  if (_quotePrefix.hasMatch(line)) return MarkdownLineStyle.quote;
  if (_bulletPrefix.hasMatch(line)) return MarkdownLineStyle.bullet;
  if (_orderedPrefix.hasMatch(line)) return MarkdownLineStyle.ordered;
  return MarkdownLineStyle.paragraph;
}

String _prefixFor(MarkdownLineStyle style, int number) => switch (style) {
  MarkdownLineStyle.paragraph => '',
  MarkdownLineStyle.heading2 => '## ',
  MarkdownLineStyle.heading3 => '### ',
  MarkdownLineStyle.heading4 => '#### ',
  MarkdownLineStyle.quote => '> ',
  MarkdownLineStyle.bullet => '- ',
  MarkdownLineStyle.ordered => '$number. ',
};

/// The start and end offsets of the whole lines the selection touches.
(int, int) _lineRange(String text, TextSelection selection) {
  final start = selection.start == 0
      ? 0
      : text.lastIndexOf('\n', selection.start - 1) + 1;
  var endProbe = selection.end;
  // A selection that ends right after a line break does not include the
  // next (untouched) line.
  if (selection.end > selection.start &&
      endProbe > 0 &&
      text.codeUnitAt(endProbe - 1) == 0x0A) {
    endProbe--;
  }
  final newline = text.indexOf('\n', endProbe);
  return (start, newline < 0 ? text.length : newline);
}

/// The style of the line the caret (or the selection's start) is on.
MarkdownLineStyle currentLineStyle(TextEditingValue value) {
  final text = value.text;
  final (start, end) = _lineRange(
    text,
    TextSelection.collapsed(offset: _selectionOf(value).start),
  );
  return lineStyleOf(text.substring(start, end));
}

/// Applies [style] to every line the selection touches, replacing whatever
/// marker they had. When every written line already has [style], the lines
/// become plain paragraphs instead, so each toolbar button toggles.
///
/// Ordered lists are numbered from 1 in the order of the lines.
TextEditingValue toggleLineStyle(
  TextEditingValue value,
  MarkdownLineStyle style,
) {
  final text = value.text;
  final selection = _selectionOf(value);
  final (start, end) = _lineRange(text, selection);
  final lines = text.substring(start, end).split('\n');
  final written = lines.where((line) => line.trim().isNotEmpty).toList();
  final alreadyStyled =
      style != MarkdownLineStyle.paragraph &&
      written.isNotEmpty &&
      written.every((line) => lineStyleOf(line) == style);
  final target = alreadyStyled ? MarkdownLineStyle.paragraph : style;

  var number = 0;
  final caretLine = selection.isCollapsed
      ? text.substring(start, selection.start).split('\n').length - 1
      : -1;
  var caretColumn = 0;
  final rewritten = <String>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final prefix = _linePrefix.firstMatch(line)?.group(0) ?? '';
    final body = line.substring(prefix.length);
    // A blank line inside a multi-line selection stays blank; a lone empty
    // line is where the author is about to type, so it takes the marker.
    final keepBlank = line.trim().isEmpty && lines.length > 1;
    final next = keepBlank ? line : _prefixFor(target, ++number) + body;
    if (index == caretLine) {
      final lineStart =
          start +
          lines.take(index).fold<int>(0, (sum, item) => sum + item.length + 1);
      final column = selection.start - lineStart;
      final inBody = (column - prefix.length).clamp(0, body.length);
      caretColumn = keepBlank ? column : next.length - body.length + inBody;
    }
    rewritten.add(next);
  }
  final block = rewritten.join('\n');
  final newText = text.substring(0, start) + block + text.substring(end);
  if (caretLine >= 0) {
    final lineStart =
        start +
        rewritten
            .take(caretLine)
            .fold<int>(0, (sum, item) => sum + item.length + 1);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + caretColumn),
    );
  }
  return TextEditingValue(
    text: newText,
    selection: TextSelection(
      baseOffset: start,
      extentOffset: start + block.length,
    ),
  );
}

/// The heading button walks through the three heading levels no-wave keeps,
/// then back to a paragraph.
TextEditingValue cycleHeading(TextEditingValue value) {
  final next = switch (currentLineStyle(value)) {
    MarkdownLineStyle.heading2 => MarkdownLineStyle.heading3,
    MarkdownLineStyle.heading3 => MarkdownLineStyle.heading4,
    MarkdownLineStyle.heading4 => MarkdownLineStyle.paragraph,
    _ => MarkdownLineStyle.heading2,
  };
  return toggleLineStyle(value, next);
}

/// Replaces the selection with [block] standing on its own, separated from
/// the text around it by a blank line, as a no-wave block must be.
///
/// The caret lands [caretInBlock] characters into the block, or after it.
TextEditingValue insertBlock(
  TextEditingValue value,
  String block, {
  int? caretInBlock,
}) {
  final text = value.text;
  final selection = _selectionOf(value);
  final before = text.substring(0, selection.start);
  final after = text.substring(selection.end);
  final lead = before.isEmpty || before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trail = after.isEmpty
      ? '\n'
      : after.startsWith('\n\n')
      ? ''
      : after.startsWith('\n')
      ? '\n'
      : '\n\n';
  final head = before + lead;
  return TextEditingValue(
    text: head + block + trail + after,
    selection: TextSelection.collapsed(
      offset: head.length + (caretInBlock ?? block.length + trail.length),
    ),
  );
}

/// A fenced code block. Selected text becomes its code; otherwise the caret
/// waits on the empty line inside the fence.
TextEditingValue insertCodeBlock(TextEditingValue value) {
  final selection = _selectionOf(value);
  final selected = value.text.substring(selection.start, selection.end);
  var longest = 0;
  for (final run in RegExp('`+').allMatches(selected)) {
    if (run.group(0)!.length > longest) longest = run.group(0)!.length;
  }
  final fence = '`' * (longest >= 3 ? longest + 1 : 3);
  final block = '$fence\n$selected\n$fence';
  return insertBlock(
    value,
    block,
    caretInBlock: fence.length + 1 + selected.length,
  );
}

/// A picture on its own line. The caret waits inside the brackets, where the
/// author can describe the picture for readers who cannot see it.
TextEditingValue insertImage(TextEditingValue value, String url) {
  return insertBlock(value, '![]($url)', caretInBlock: 2);
}

/// A link around the selected words, or around [label] (the address itself
/// when there is none) at the caret.
TextEditingValue insertLink(
  TextEditingValue value,
  String url, {
  String label = '',
}) {
  final text = value.text;
  final selection = _selectionOf(value);
  final selected = text.substring(selection.start, selection.end);
  final words = selected.trim().isNotEmpty
      ? selected
      : label.trim().isNotEmpty
      ? label.trim()
      : url;
  final escaped = words.replaceAllMapped(
    RegExp(r'[\[\]\\]'),
    (match) => '\\${match.group(0)}',
  );
  final link = '[$escaped]($url)';
  final before = text.substring(0, selection.start);
  return TextEditingValue(
    text: before + link + text.substring(selection.end),
    selection: TextSelection.collapsed(offset: before.length + link.length),
  );
}

final _continuable = RegExp(
  r'^([ \t]*)(?:([-*+])|(\d{1,9})([.)])|(>))([ \t]*)',
);
final _fenceLine = RegExp(r'^[ \t]*(?:`{3,}|~{3,})');

/// Continues a list or quote when the author presses Enter at the end of an
/// item, the way every writing app does: `- milk⏎` gives `- `, `3. eggs⏎`
/// gives `4. `, `> said⏎` gives `> `. Enter on an item that is still empty
/// ends the list instead, leaving a plain empty line.
///
/// Answers null when [newValue] is not exactly one line break typed at a
/// caret, so the formatter leaves every other edit alone.
TextEditingValue? continueMarkdownBlock(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final oldSelection = oldValue.selection;
  final newSelection = newValue.selection;
  if (!oldSelection.isValid ||
      !oldSelection.isCollapsed ||
      !newSelection.isCollapsed ||
      newValue.composing.isValid) {
    return null;
  }
  final caret = oldSelection.baseOffset;
  final old = oldValue.text;
  if (caret < 0 ||
      caret > old.length ||
      newSelection.baseOffset != caret + 1 ||
      newValue.text != '${old.substring(0, caret)}\n${old.substring(caret)}') {
    return null;
  }
  final lineStart = caret == 0 ? 0 : old.lastIndexOf('\n', caret - 1) + 1;
  final line = old.substring(lineStart, caret);
  final match = _continuable.firstMatch(line);
  if (match == null) return null;
  // A bullet needs its space; `-` or `2.` alone is ordinary text.
  final isQuote = match.group(5) != null;
  if (!isQuote && match.group(6)!.isEmpty) return null;
  // Inside a fenced code block, Enter is just a line break.
  final fences = old
      .substring(0, lineStart)
      .split('\n')
      .where(_fenceLine.hasMatch)
      .length;
  if (fences.isOdd) return null;

  final rest = line.substring(match.end);
  final lineEnd = old.indexOf('\n', caret);
  final trailing = old.substring(caret, lineEnd < 0 ? old.length : lineEnd);
  if (rest.trim().isEmpty) {
    // Enter between a marker and its text is an ordinary line break.
    if (trailing.trim().isNotEmpty) return null;
    // Ending the list: drop the empty marker, keep the caret on that line.
    final text = old.substring(0, lineStart) + old.substring(caret);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: lineStart),
    );
  }
  final indent = match.group(1)!;
  final String marker;
  if (isQuote) {
    marker = '$indent> ';
  } else if (match.group(2) case final String bullet) {
    marker = '$indent$bullet ';
  } else {
    final number = int.parse(match.group(3)!) + 1;
    marker = '$indent$number${match.group(4)} ';
  }
  final head = '${old.substring(0, caret)}\n$marker';
  return TextEditingValue(
    text: head + old.substring(caret),
    selection: TextSelection.collapsed(offset: head.length),
  );
}

/// Applies [continueMarkdownBlock] as the body field's input formatter.
class MarkdownContinuationFormatter extends TextInputFormatter {
  const MarkdownContinuationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return continueMarkdownBlock(oldValue, newValue) ?? newValue;
  }
}

final _hiddenTarget = RegExp(r'\]\([^)\s]*\)');
final _hanCharacter = RegExp(
  r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]',
);
final _latinWord = RegExp(r"[A-Za-z0-9\u00C0-\u024F]+(?:['\u2019][A-Za-z]+)*");

/// How many words the author has written: every CJK character counts as one,
/// as Chinese writers count 字, and every Latin word as one. Link and image
/// addresses are not words the reader will read, so they do not count.
int countArticleWords(String text) {
  final readable = text.replaceAll(_hiddenTarget, ']');
  return _hanCharacter.allMatches(readable).length +
      _latinWord.allMatches(readable).length;
}
