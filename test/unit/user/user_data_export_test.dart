import 'package:belog/core/common/entities/user.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the export documents the profile and every article (issue #22)',
    () async {
      final user = User(
        id: 'u1',
        email: 'author@example.invalid',
        name: '作者',
        updatedAt: DateTime.utc(2026, 10, 1, 8, 30),
        avatarUrl: 'https://api.example.invalid/a.webp',
        website: 'https://example.invalid',
      );
      final articles = [
        Blog(
          id: 'my-slug',
          title: '标题',
          content: '# 正文',
          posterId: 'u1',
          imageUrl: '',
          tags: const ['诗歌', '原创'],
          updatedAt: DateTime.utc(2026, 10, 2, 9),
          posterName: '作者',
        ),
      ];

      final document = buildUserDataExport(
        user: user,
        articles: articles,
        now: DateTime.utc(2026, 10, 30, 12),
      );

      expect(document['format'], 'belog-user-data-export');
      expect(document['version'], 1);
      expect(document['exportedAt'], '2026-10-30T12:00:00.000Z');

      final profile = document['profile']! as Map<String, Object?>;
      expect(profile['id'], 'u1');
      expect(profile['email'], 'author@example.invalid');
      expect(profile['name'], '作者');
      expect(profile['website'], 'https://example.invalid');
      expect(profile['updatedAt'], '2026-10-01T08:30:00.000Z');

      final exported = document['articles']! as List<Map<String, Object?>>;
      expect(exported, hasLength(1));
      expect(exported.single['slug'], 'my-slug');
      expect(exported.single['title'], '标题');
      expect(exported.single['content'], '# 正文');
      expect(exported.single['tags'], ['诗歌', '原创']);
      expect(exported.single['imageUrl'], '');
      expect(exported.single['updatedAt'], '2026-10-02T09:00:00.000Z');
    },
  );

  test('an account without articles exports an empty list', () async {
    final user = User(
      id: 'u1',
      email: 'author@example.invalid',
      name: '作者',
      updatedAt: DateTime.utc(2026, 10, 1),
    );

    final document = buildUserDataExport(
      user: user,
      articles: const [],
      now: DateTime.utc(2026, 10, 30),
    );

    expect(document['articles'], isEmpty);
    expect(
      (document['profile']! as Map<String, Object?>)['id'],
      'u1',
    );
  });
}
