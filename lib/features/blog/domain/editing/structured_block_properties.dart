import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// An edit of block properties is bound to the exact immutable body on which
/// the author made the selection. It never infers a block from position or
/// removes unrelated properties, inline runs, or other blocks.
sealed class StructuredBlockProperties {
  const StructuredBlockProperties({required this.body, required this.blockId});

  final StructuredArticleDraft body;
  final String blockId;

  Map<String, Object?> _selected(StructuredArticleDraft current, String type) {
    if (!identical(body, current)) {
      throw StateError('The selected body has changed');
    }
    final blocks = current.blocks.where((block) => block['id'] == blockId);
    if (blocks.length != 1 || blocks.single['type'] != type) {
      throw StateError('The selected block is no longer available');
    }
    return blocks.single;
  }

  StructuredArticleDraft apply(StructuredArticleDraft current);

  static void _renderable(String value) {
    if (!isWellFormedUtf16(value)) {
      throw const FormatException('Text contains invalid UTF-16');
    }
  }
}

/// Replaces only image alt and optional caption. An absent caption is distinct
/// from an explicitly present empty string. The image URL is never changed.
final class StructuredImageProperties extends StructuredBlockProperties {
  const StructuredImageProperties({
    required super.body,
    required super.blockId,
    required this.alt,
    required this.captionPresent,
    required this.caption,
  });
  final String alt;
  final bool captionPresent;
  final String caption;

  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = _selected(current, 'image');
    StructuredBlockProperties._renderable(alt);
    if (captionPresent) StructuredBlockProperties._renderable(caption);
    final next = Map<String, Object?>.of(block)..['alt'] = alt;
    if (captionPresent) {
      next['caption'] = caption;
    } else {
      next.remove('caption');
    }
    return current.replace(blockId, next);
  }
}

/// Code and its language remain literal strings; they are not normalized,
/// executed, rendered as Markdown, or passed to a remote service.
final class StructuredCodeProperties extends StructuredBlockProperties {
  const StructuredCodeProperties({
    required super.body,
    required super.blockId,
    required this.language,
    required this.code,
  });
  final String language;
  final String code;

  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = _selected(current, 'code');
    StructuredBlockProperties._renderable(language);
    StructuredBlockProperties._renderable(code);
    return current.replace(blockId, {
      ...block,
      'language': language,
      'code': code,
    });
  }
}

/// Quote content and runs are never rebuilt when the attribution changes.
final class StructuredQuoteProperties extends StructuredBlockProperties {
  const StructuredQuoteProperties({
    required super.body,
    required super.blockId,
    required this.attributionPresent,
    required this.attribution,
  });
  final bool attributionPresent;
  final String attribution;

  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = _selected(current, 'quote');
    if (attributionPresent) StructuredBlockProperties._renderable(attribution);
    final next = Map<String, Object?>.of(block);
    if (attributionPresent) {
      next['attribution'] = attribution;
    } else {
      next.remove('attribution');
    }
    return current.replace(blockId, next);
  }
}

/// Heading runs and text are preserved exactly while changing its level.
final class StructuredHeadingProperties extends StructuredBlockProperties {
  const StructuredHeadingProperties({
    required super.body,
    required super.blockId,
    required this.level,
  });
  final int level;
  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = _selected(current, 'heading');
    return current.replace(blockId, {...block, 'level': level});
  }
}

/// Changing ordered/unordered list presentation never changes its items or
/// itemInlines. List indices are not used as persistent identities.
final class StructuredListProperties extends StructuredBlockProperties {
  const StructuredListProperties({
    required super.body,
    required super.blockId,
    required this.ordered,
  });
  final bool ordered;
  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = _selected(current, 'list');
    return current.replace(blockId, {...block, 'ordered': ordered});
  }
}
