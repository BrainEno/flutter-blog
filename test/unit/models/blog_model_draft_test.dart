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

  test('the categories the server joined become ids, not names', () {
    final model = BlogModel.fromNowaveArticle({
      ..._row(),
      'categories': const [
        {'id': 'cat-1', 'slug': 'essay', 'name': '随笔'},
        {'id': 'cat-2', 'slug': 'poem', 'name': '诗'},
      ],
    });

    // The write names ids; names are per language and come from the catalog.
    expect(model.categoryIds, ['cat-1', 'cat-2']);
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
    expect(model.copyWith(categoryIds: const []).categoryIds, isEmpty);
  });

  test('copyWith preserves the draft flag', () {
    final draft = BlogModel.fromNowaveArticle(_row(status: 'draft'));

    expect(draft.copyWith(title: '新标题').isDraft, isTrue);
  });
}
