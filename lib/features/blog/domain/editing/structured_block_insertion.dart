import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// Six document shapes supported by the current local v0/v1 validator. This is
/// not a remote create command and does not imply server write compatibility.
enum StructuredNewBlockKind { paragraph, heading, quote, list, image, code }

/// Values from an explicitly confirmed temporary form. The command binds both
/// the destination and the new values to an exact immutable body snapshot.
/// It neither normalizes text nor guesses optional-field presence.
final class StructuredBlockInsertion {
  const StructuredBlockInsertion({
    required this.source,
    required this.afterBlockId,
    required this.newBlockId,
    required this.kind,
    this.text = '',
    this.secondary = '',
    this.optionalPresent = false,
    this.optionalText = '',
    this.headingLevel = 2,
    this.ordered = false,
  });

  final StructuredArticleDraft source;
  final String afterBlockId;
  final String newBlockId;
  final StructuredNewBlockKind kind;
  final String text;
  final String secondary;
  final bool optionalPresent;
  final String optionalText;
  final int headingLevel;
  final bool ordered;

  StructuredArticleDraft apply(StructuredArticleDraft current) {
    if (!identical(source, current)) {
      throw StateError('Insertion destination changed');
    }
    final index = current.blocks.indexWhere(
      (block) => block['id'] == afterBlockId,
    );
    if (index < 0) throw StateError('Insertion anchor is unavailable');
    if (!isWellFormedUtf16(newBlockId) ||
        !isWellFormedUtf16(text) ||
        !isWellFormedUtf16(secondary) ||
        (optionalPresent && !isWellFormedUtf16(optionalText))) {
      throw const FormatException('Invalid UTF-16');
    }
    final Map<String, Object?> block = switch (kind) {
      StructuredNewBlockKind.paragraph => {
        'id': newBlockId,
        'type': 'paragraph',
        'text': text,
      },
      StructuredNewBlockKind.heading => {
        'id': newBlockId,
        'type': 'heading',
        'text': text,
        'level': headingLevel,
      },
      StructuredNewBlockKind.quote => {
        'id': newBlockId,
        'type': 'quote',
        'text': text,
        if (optionalPresent) 'attribution': optionalText,
      },
      StructuredNewBlockKind.list => {
        'id': newBlockId,
        'type': 'list',
        'ordered': ordered,
        'items': [text],
      },
      StructuredNewBlockKind.image => {
        'id': newBlockId,
        'type': 'image',
        'src': text,
        'alt': secondary,
        if (optionalPresent) 'caption': optionalText,
      },
      StructuredNewBlockKind.code => {
        'id': newBlockId,
        'type': 'code',
        'language': text,
        'code': secondary,
      },
    };
    // insert validates all schema limits, URL rules, unique IDs and size.
    return current.insert(index + 1, block);
  }
}
