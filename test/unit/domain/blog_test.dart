import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/blog_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Blog Entity', () {
    test('should create a Blog with all required fields', () {
      final blog = Blog(
        id: 'blog_123',
        title: 'Test Blog',
        content: 'Test content',
        posterId: 'user_456',
        imageUrl: 'https://example.com/image.jpg',
        tags: ['tag1', 'tag2'],
        updatedAt: DateTime(2024, 1, 1),
        posterName: 'John Doe',
        posterAvatar: 'https://example.com/avatar.jpg',
      );

      expect(blog.id, 'blog_123');
      expect(blog.title, 'Test Blog');
      expect(blog.content, 'Test content');
      expect(blog.posterId, 'user_456');
      expect(blog.imageUrl, 'https://example.com/image.jpg');
      expect(blog.tags, ['tag1', 'tag2']);
      expect(blog.updatedAt, DateTime(2024, 1, 1));
      expect(blog.posterName, 'John Doe');
      expect(blog.posterAvatar, 'https://example.com/avatar.jpg');
    });

    test('should create a Blog with optional fields as null', () {
      final blog = Blog(
        id: 'blog_123',
        title: 'Test Blog',
        content: 'Test content',
        posterId: 'user_456',
        imageUrl: 'https://example.com/image.jpg',
        tags: ['tag1'],
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(blog.posterName, isNull);
      expect(blog.posterAvatar, isNull);
    });

    test('is a plain Dart entity with no persistence imports', () {
      // Regression guard for the domain-purity requirement: the entity must
      // stay free of Isar/Drift annotations and auto-increment keys.
      expect(
        Blog(
          id: 'a',
          title: 't',
          content: 'c',
          posterId: 'p',
          imageUrl: 'i',
          tags: const [],
          updatedAt: DateTime(2024, 1, 1),
        ).id,
        isA<String>(),
      );
    });
  });

  group('BlogDraft Entity', () {
    test('starts without a local row id until the store assigns one', () {
      final draft = BlogDraft(
        blogId: 'blog_123',
        title: 'title',
        content: 'content',
        tags: ['tag'],
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(draft.id, isNull);
      expect(draft.blogId, 'blog_123');

      // The store assigns the local row id after persisting.
      draft.id = 7;
      expect(draft.id, 7);
    });

    test('supports a null blogId for new-article drafts', () {
      final draft = BlogDraft(
        title: 'title',
        content: 'content',
        tags: const [],
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(draft.blogId, isNull);
    });
  });
}
