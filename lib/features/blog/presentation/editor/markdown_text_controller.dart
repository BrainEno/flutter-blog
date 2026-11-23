import 'package:flutter/material.dart';

/// The three looks the editor's live highlighting uses.
///
/// [base] is the body text, [faded] the Markdown signs themselves (they are
/// still there and editable, just quieter), and [accent] list and quote
/// markers and link words - the things that show structure at a glance.
class MarkdownHighlightStyles {
  const MarkdownHighlightStyles({
    required this.base,
    required this.faded,
    required this.accent,
  });

  final TextStyle base;
  final TextStyle faded;
  final TextStyle accent;
}

final _fence = RegExp(r'^[ \t]*(`{3,}|~{3,})');
final _heading = RegExp(r'^([ \t]*#{1,6}[ \t]+)(.*)$');
final _quote = RegExp(r'^([ \t]*>[ \t]?)(.*)$');
final _listItem = RegExp(r'^([ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+)(.*)$');
final _image = RegExp(r'^[ \t]*!\[[^\]]*\]\([^)\s]*\)[ \t]*$');

// One alternative per inline construct; the earliest match in a line wins.
// Groups: 1 escape | 2,3 code | 4 bold | 5 strike | 6 underline |
// 7 italic (*) | 8 italic (_) | 9 label, 10 address of a link.
final _inline = RegExp(
  r'(\\[!-/:-@\[-`{-~])'
  r'|(`+)(.+?)\2'
  r'|\*\*(?=\S)(.+?)(?<=\S)\*\*'
  r'|~~(?=\S)(.+?)(?<=\S)~~'
  r'|<u>(.+?)</u>'
  r'|(?<![*\\])\*(?=[^\s*])(.+?)(?<=[^\s*\\])\*(?!\*)'
  r'|(?<![A-Za-z0-9_\\])_(?=\S)(.+?)(?<=\S)_(?![A-Za-z0-9_])'
  r'|(?<!!)\[([^\]]+)\]\(([^)\s]+)\)',
);

/// Collects consecutive pieces of text, underlining the IME composing range
/// (the pinyin being typed) the way a plain field does.
class _Sink {
  _Sink(this.composing);

  final TextRange composing;
  final spans = <TextSpan>[];
  var _offset = 0;

  void add(String text, TextStyle style) {
    if (text.isEmpty) return;
    final start = _offset;
    final end = start + text.length;
    _offset = end;
    if (!composing.isValid ||
        composing.isCollapsed ||
        composing.end <= start ||
        composing.start >= end) {
      spans.add(TextSpan(text: text, style: style));
      return;
    }
    final from = (composing.start - start).clamp(0, text.length);
    final to = (composing.end - start).clamp(0, text.length);
    if (from > 0) {
      spans.add(TextSpan(text: text.substring(0, from), style: style));
    }
    spans.add(
      TextSpan(
        text: text.substring(from, to),
        style: style.merge(
          const TextStyle(decoration: TextDecoration.underline),
        ),
      ),
    );
    if (to < text.length) {
      spans.add(TextSpan(text: text.substring(to), style: style));
    }
  }
}

/// Splits Markdown [text] into styled spans whose texts, joined, are exactly
/// [text] - an editable field requires that, character for character.
///
/// Headings turn bold, emphasis shows as emphasis, and the signs that make
/// them fade back, so the author sees the structure without a preview.
List<TextSpan> highlightMarkdown(
  String text,
  MarkdownHighlightStyles styles, {
  TextRange composing = TextRange.empty,
}) {
  final sink = _Sink(composing);
  final lines = text.split('\n');
  var inCode = false;
  String? fenceMarker;
  for (var index = 0; index < lines.length; index++) {
    if (index > 0) sink.add('\n', styles.base);
    final line = lines[index];
    final fence = _fence.firstMatch(line);
    if (inCode) {
      sink.add(line, styles.faded);
      if (fence != null && fence.group(1)!.startsWith(fenceMarker!)) {
        inCode = false;
      }
      continue;
    }
    if (fence != null) {
      inCode = true;
      fenceMarker = fence.group(1);
      sink.add(line, styles.faded);
      continue;
    }
    if (_image.hasMatch(line)) {
      sink.add(line, styles.faded);
      continue;
    }
    if (_heading.firstMatch(line) case final RegExpMatch heading) {
      final strong = styles.base.copyWith(fontWeight: FontWeight.w700);
      sink.add(heading.group(1)!, styles.faded);
      _addInline(sink, heading.group(2)!, strong, styles);
      continue;
    }
    if (_quote.firstMatch(line) case final RegExpMatch quote) {
      sink.add(quote.group(1)!, styles.accent);
      _addInline(
        sink,
        quote.group(2)!,
        styles.base.copyWith(fontStyle: FontStyle.italic),
        styles,
      );
      continue;
    }
    if (_listItem.firstMatch(line) case final RegExpMatch item) {
      sink.add(
        item.group(1)!,
        styles.accent.copyWith(fontWeight: FontWeight.w700),
      );
      _addInline(sink, item.group(2)!, styles.base, styles);
      continue;
    }
    _addInline(sink, line, styles.base, styles);
  }
  return sink.spans;
}

void _addInline(
  _Sink sink,
  String text,
  TextStyle style,
  MarkdownHighlightStyles styles,
) {
  final faded = style.merge(
    TextStyle(color: styles.faded.color, fontWeight: FontWeight.w400),
  );
  var cursor = 0;
  while (cursor < text.length) {
    final match = _inline.firstMatch(text.substring(cursor));
    if (match == null) break;
    final start = cursor + match.start;
    sink.add(text.substring(cursor, start), style);
    final whole = match.group(0)!;
    if (match.group(1) != null) {
      sink
        ..add('\\', faded)
        ..add(whole.substring(1), style);
    } else if (match.group(2) case final String ticks) {
      sink
        ..add(ticks, faded)
        ..add(match.group(3)!, style.merge(styles.accent))
        ..add(ticks, faded);
    } else if (match.group(4) case final String inner) {
      _wrapped(sink, '**', inner, '**', faded, styles, () {
        return style.copyWith(fontWeight: FontWeight.w700);
      });
    } else if (match.group(5) case final String inner) {
      _wrapped(sink, '~~', inner, '~~', faded, styles, () {
        return style.copyWith(decoration: TextDecoration.lineThrough);
      });
    } else if (match.group(6) case final String inner) {
      _wrapped(sink, '<u>', inner, '</u>', faded, styles, () {
        return style.copyWith(decoration: TextDecoration.underline);
      });
    } else if (match.group(7) case final String inner) {
      _wrapped(sink, '*', inner, '*', faded, styles, () {
        return style.copyWith(fontStyle: FontStyle.italic);
      });
    } else if (match.group(8) case final String inner) {
      _wrapped(sink, '_', inner, '_', faded, styles, () {
        return style.copyWith(fontStyle: FontStyle.italic);
      });
    } else {
      sink.add('[', faded);
      _addInline(
        sink,
        match.group(9)!,
        style.merge(
          styles.accent.copyWith(decoration: TextDecoration.underline),
        ),
        styles,
      );
      sink.add('](${match.group(10)!})', faded);
    }
    cursor = start + whole.length;
  }
  sink.add(text.substring(cursor), style);
}

void _wrapped(
  _Sink sink,
  String open,
  String inner,
  String close,
  TextStyle faded,
  MarkdownHighlightStyles styles,
  TextStyle Function() innerStyle,
) {
  sink.add(open, faded);
  _addInline(sink, inner, innerStyle(), styles);
  sink.add(close, faded);
}

/// The body field's controller: the text stays plain Markdown - what is saved,
/// drafted and published - while the field paints it with [highlightMarkdown].
class MarkdownTextController extends TextEditingController {
  MarkdownTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final scheme = Theme.of(context).colorScheme;
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    return TextSpan(
      style: base,
      children: highlightMarkdown(
        text,
        MarkdownHighlightStyles(
          base: base,
          faded: base.copyWith(color: scheme.onSurfaceVariant),
          accent: base.copyWith(color: scheme.primary),
        ),
        composing: composing,
      ),
    );
  }
}
