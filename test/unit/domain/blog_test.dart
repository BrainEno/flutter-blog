import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Blog Entity', () {
    test('should create a Blog with all required fields', () {
      final blog = Blog(
        iid: 1,
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

      expect(blog.iid, 1);
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
        iid: 1,
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

    test('titleWords getter should split title by spaces', () {
      final blog = Blog(
        iid: 1,
        id: 'blog_123',
        title: 'Hello World Test',
        content: 'Test content',
        posterId: 'user_456',
        imageUrl: 'https://example.com/image.jpg',
        tags: ['tag1'],
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(blog.titleWords, ['Hello', 'World', 'Test']);
    });

    test('titleWords getter handles single word', () {
      final blog = Blog(
        iid: 1,
        id: 'blog_123',
        title: 'Single',
        content: 'Test content',
        posterId: 'user_456',
        imageUrl: 'https://example.com/image.jpg',
        tags: ['tag1'],
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(blog.titleWords, ['Single']);
    });
  });
}