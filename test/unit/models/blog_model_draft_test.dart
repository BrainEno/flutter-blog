import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({String? status}) => <String, dynamic>{
  'id': '11111111-1111-1111-1111-111111111111',
  'slug': 'a-slug',
  'title': '标题',
  'summary': '',
  if (status != null) 'status': status,
  'contentBlocks': const [
    {'type': 'paragraph', 'text': '正文'},
  ],
  'contentBlocksVersion': 0,
  'authorId': 'author',
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

void main() {
  test('the author\'s own draft row is marked as a draft', () {
    final model = BlogModel.fromNowaveArticle(_row(status: 'draft'));

    expect(model.isDraft, isTrue);
    // A draft keeps the addresses needed to edit and publish it again.
    expect(model.articleId, '11111111-1111-1111-1111-111111111111');
    expect(model.id, 'a-slug');
  });

  test('a published row is not a draft', () {
    final model = BlogModel.fromNowaveArticle(_row(status: 'published'));

    expect(model.isDraft, isFalse);
  });

  test('rows without a status (public lists) are never drafts', () {
    expect(BlogModel.fromNowaveArticle(_row()).isDraft, isFalse);
  });

  test('the categories the server joined keep both the ids and the names', () {
    final model = BlogModel.fromNowaveArticle({
      ..._row(),
      'categories': const [
        {'id': 'cat-1', 'slug': 'essay', 'name': '随笔'},
        {
          'id': 'cat-2',
          'slug': 'poem',
          'name': 'Poetry',
          'description': 'Verse.',
        },
      ],
    });

    // The write names ids; the reader shows the names this edition carries,
    // which is why the article response is enough to draw the chips.
    expect(model.categoryIds, ['cat-1', 'cat-2']);
    expect(model.categories.map((c) => c.name), ['随笔', 'Poetry']);
    expect(model.categories.first.slug, 'essay');
    expect(model.categories.last.description, 'Verse.');
  });

  test('an unusable category entry is dropped, not fatal', () {
    final model = BlogModel.fromNowaveArticle({
      ..._row(),
      'categories': const [
        {'id': 'cat-1', 'slug': '', 'name': '没有地址'},
        {'id': 'cat-2', 'slug': 'no-name'},
        'not an object',
        {'id': 'cat-3', 'slug': 'essay', 'name': '随笔'},
        // One address per category: the second row would go nowhere new.
        {'id': 'cat-4', 'slug': 'essay', 'name': '随笔二'},
      ],
    });

    expect(model.categoryIds, ['cat-3']);
    expect(model.categories.single.name, '随笔');
  });

  test('a row without categories is empty, not unknown', () {
    expect(BlogModel.fromNowaveArticle(_row()).categoryIds, isEmpty);
  });

  test('copyWith keeps the categories unless it is told otherwise', () {
    final model = BlogModel.fromNowaveArticle({
      ..._row(),
      'categories': const [
        {'id': 'cat-1', 'slug': 'essay', 'name': '随笔'},
      ],
    });

    expect(model.copyWith(title: '新标题').categoryIds, ['cat-1']);
    // A copy keeps the names it did not touch: dropping them would blank the
    // chips on the next frame.
    expect(model.copyWith(title: '新标题').categories.single.name, '随笔');
    expect(model.copyWith(categoryIds: const []).categoryIds, isEmpty);
    expect(model.copyWith(categoryIds: const ['cat-9']).categoryIds, [
      'cat-9',
    ]);
  });

  test('copyWith preserves the draft flag', () {
    final draft = BlogModel.fromNowaveArticle(_row(status: 'draft'));

    expect(draft.copyWith(title: '新标题').isDraft, isTrue);
  });
}
