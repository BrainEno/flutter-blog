import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// A list item has no persistent identity in the server document. Every action
/// therefore binds the index to the exact body from which the user selected it.
/// Actions validate a complete replacement before the local session accepts it.
sealed class StructuredListAction {
  const StructuredListAction({required this.source, required this.blockId});

  final StructuredArticleDraft source;
  final String blockId;

  Map<String, Object?> selected(StructuredArticleDraft current) {
    if (!identical(source, current)) {
      throw StateError('List snapshot changed');
    }
    final blocks = current.blocks.where((block) => block['id'] == blockId);
    if (blocks.length != 1 || blocks.single['type'] != 'list') {
      throw StateError('List is no longer available');
    }
    return blocks.single;
  }

  StructuredArticleDraft apply(StructuredArticleDraft current);

  StructuredArticleDraft replace(
    StructuredArticleDraft current,
    Map<String, Object?> block,
    List<Object?> items,
    List<Object?>? itemInlines,
  ) {
    return current.replace(blockId, {
      ...block,
      'items': items,
      if (itemInlines != null) 'itemInlines': itemInlines,
    });
  }
}

/// Insert a literal unformatted item. If the list already carries inline runs,
/// the new item receives its own plain run, while all existing runs are copied
/// untouched. An unformatted list is never promoted implicitly.
final class StructuredListInsert extends StructuredListAction {
  const StructuredListInsert({
    required super.source,
    required super.blockId,
    required this.index,
    required this.text,
  });
  final int index;
  final String text;

  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = selected(current);
    if (!isWellFormedUtf16(text)) {
      throw const FormatException('Invalid UTF-16');
    }
    final items = List<Object?>.of(block['items'] as List);
    if (index < 0 || index > items.length) {
      throw RangeError.range(index, 0, items.length, 'index');
    }
    items.insert(index, text);
    final existing = block['itemInlines'];
    final inlines = existing is List ? List<Object?>.of(existing) : null;
    inlines?.insert(index, [
      <String, Object?>{'text': text},
    ]);
    return replace(current, block, items, inlines);
  }
}

/// Move an item and the corresponding run array as one indivisible operation.
/// [destination] is the final zero-based index, not the pre-removal index.
final class StructuredListMove extends StructuredListAction {
  const StructuredListMove({
    required super.source,
    required super.blockId,
    required this.index,
    required this.destination,
  });
  final int index;
  final int destination;

  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = selected(current);
    final items = List<Object?>.of(block['items'] as List);
    RangeError.checkValidIndex(index, items, 'index');
    RangeError.checkValidIndex(destination, items, 'destination');
    if (index == destination) return current;
    items.insert(destination, items.removeAt(index));
    final existing = block['itemInlines'];
    final inlines = existing is List ? List<Object?>.of(existing) : null;
    if (inlines != null) {
      inlines.insert(destination, inlines.removeAt(index));
    }
    return replace(current, block, items, inlines);
  }
}

/// Remove an exact selected item and its runs. Refuses to remove the last item
/// because an empty list is not a valid document; remove the block instead.
final class StructuredListRemove extends StructuredListAction {
  const StructuredListRemove({
    required super.source,
    required super.blockId,
    required this.index,
  });
  final int index;

  @override
  StructuredArticleDraft apply(StructuredArticleDraft current) {
    final block = selected(current);
    final items = List<Object?>.of(block['items'] as List);
    RangeError.checkValidIndex(index, items, 'index');
    if (items.length <= 1) {
      throw StateError('A list must contain at least one item');
    }
    items.removeAt(index);
    final existing = block['itemInlines'];
    final inlines = existing is List ? List<Object?>.of(existing) : null;
    inlines?.removeAt(index);
    return replace(current, block, items, inlines);
  }
}
