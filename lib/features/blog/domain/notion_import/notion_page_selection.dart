import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';

/// What choosing pages of a bundle needs to know about them: which pages
/// travel together, and which of the export's local images each one uses.
///
/// A work and its translation are imported together - the server refuses
/// one without the other - so the pages an `English` relation links are
/// selected and unselected as one group.
class NotionPageSelection {
  NotionPageSelection._(this.pageCount, this._partners, this._images);

  factory NotionPageSelection.of(NotionBundle bundle) {
    final pages = bundle.json['pages'] as List;
    return NotionPageSelection._(pages.length, _englishPartners(pages), [
      for (final page in pages)
        {
          for (final block in (page as Map)['blocks'] as List)
            ?notionLocalImageKey(block),
        },
    ]);
  }

  /// A selection over no pages.
  static final empty = NotionPageSelection._(0, const [], const []);

  final int pageCount;
  final List<Set<int>> _partners;
  final List<Set<String>> _images;

  /// Every page: an export starts fully selected, as on the web.
  Set<int> get all => {for (var i = 0; i < pageCount; i++) i};

  /// The pages [index] is paired with, never including itself.
  Set<int> partnersOf(int index) =>
      index >= 0 && index < _partners.length ? _partners[index] : const {};

  /// [current] with page [index] and its partners added or taken out.
  Set<int> toggle(Set<int> current, int index, {required bool include}) {
    final group = {index, ...partnersOf(index)};
    final next = Set<int>.of(current);
    if (include) {
      next.addAll(group);
    } else {
      next.removeAll(group);
    }
    return next;
  }

  /// The local images the [selected] pages use.
  Set<String> imagesOf(Iterable<int> selected) => {
    for (final index in selected)
      if (index >= 0 && index < _images.length) ..._images[index],
  };

  static List<Set<int>> _englishPartners(List<dynamic> pages) {
    String normal(Object? id) => '$id'.toLowerCase().replaceAll('-', '');
    final byId = <String, int>{
      for (var i = 0; i < pages.length; i++) normal((pages[i] as Map)['id']): i,
    };
    final partners = [for (var i = 0; i < pages.length; i++) <int>{}];
    for (var i = 0; i < pages.length; i++) {
      final properties = (pages[i] as Map)['properties'];
      final english = properties is Map ? properties['English'] : null;
      final links = english is Map ? english['relation'] : null;
      if (links is! List) continue;
      for (final link in links) {
        final j = link is Map ? byId[normal(link['id'])] : null;
        if (j == null || j == i) continue;
        partners[i].add(j);
        partners[j].add(i);
      }
    }
    return partners;
  }
}
