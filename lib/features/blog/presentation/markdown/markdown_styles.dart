import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Combines two optional decorations into one (a link inside struck-through
/// text must keep both).
TextDecoration? combineDecorations(TextDecoration? a, TextDecoration? b) {
  if (a == null) return b;
  if (b == null) return a;
  return TextDecoration.combine([a, b]);
}

/// The inline marks the structured document carries - bold, italic, underline
/// and strikethrough - as a [TextStyle].
TextStyle structuredMarksStyle(md.Element node, {bool link = false}) {
  final decorations = <TextDecoration>[
    if (link || node.attributes['data-underline'] == 'true')
      TextDecoration.underline,
    if (node.attributes['data-strikethrough'] == 'true')
      TextDecoration.lineThrough,
  ];
  return TextStyle(
    fontWeight: node.attributes['data-bold'] == 'true'
        ? FontWeight.bold
        : null,
    fontStyle: node.attributes['data-italic'] == 'true'
        ? FontStyle.italic
        : null,
    decoration: decorations.isEmpty
        ? null
        : TextDecoration.combine(decorations),
  );
}
