import 'package:belog/core/utils/storage_objects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('objectPathFromPublicUrl', () {
    test('parses a legacy flat blog cover URL (path = blog id, no ext)',
        () {
      const url =
          'https://demo.supabase.co/storage/v1/object/public/blog_images/'
          '01937c2e-6d90-7bb4-a30c-8f7d0e6a1234';
      expect(
        objectPathFromPublicUrl(url),
        '01937c2e-6d90-7bb4-a30c-8f7d0e6a1234',
      );
    });

    test('parses a versioned nested cover URL', () {
      const url =
          'https://demo.supabase.co/storage/v1/object/public/blog_images/'
          'covers/u1/b1/1730000000000.jpg';
      expect(
        objectPathFromPublicUrl(url),
        'covers/u1/b1/1730000000000.jpg',
      );
    });

    test('strips cache-busting query parameters and fragments', () {
      const url =
          'https://demo.supabase.co/storage/v1/object/public/blog_images/'
          'covers/u1/b1/1730000000000.jpg?v=123456789#top';
      expect(
        objectPathFromPublicUrl(url),
        'covers/u1/b1/1730000000000.jpg',
      );
    });

    test('parses a legacy flat avatar URL', () {
      const url =
          'https://demo.supabase.co/storage/v1/object/public/avatars/u9';
      expect(objectPathFromPublicUrl(url), 'u9');
    });

    test('returns null for non-public-object URLs', () {
      expect(objectPathFromPublicUrl(''), isNull);
      expect(
        objectPathFromPublicUrl('https://example.com/blog_images/abc'),
        isNull,
      );
      expect(
        objectPathFromPublicUrl(
          'https://demo.supabase.co/storage/v1/object/public/blog_images',
        ),
        isNull, // bucket only, no object path
      );
      expect(
        objectPathFromPublicUrl(
          'https://demo.supabase.co/storage/v1/object/public/blog_images/',
        ),
        isNull, // trailing slash = empty object path
      );
    });
  });

  group('extensionForMime', () {
    test('maps known image types', () {
      expect(extensionForMime('image/jpeg'), '.jpg');
      expect(extensionForMime('image/png'), '.png');
      expect(extensionForMime('image/webp'), '.webp');
      expect(extensionForMime('image/gif'), '.gif');
      expect(extensionForMime('image/heic'), '.heic');
      expect(extensionForMime('image/heif'), '.heic');
    });

    test('unknown and missing types default to .jpg', () {
      expect(extensionForMime(null), '.jpg');
      expect(extensionForMime('application/octet-stream'), '.jpg');
    });
  });

  group('path builders', () {
    test('cover paths are poster-scoped, blog-scoped and versioned', () {
      expect(
        blogCoverObjectPath(
          posterId: 'u1',
          blogId: 'b1',
          version: '1730000000000',
          extension: '.jpg',
        ),
        'covers/u1/b1/1730000000000.jpg',
      );
    });

    test('avatar paths are user-scoped and versioned', () {
      expect(
        avatarObjectPath(
          userId: 'u9',
          version: '1730000000001',
          extension: '.png',
        ),
        'avatars/u9/1730000000001.png',
      );
    });

    test('built paths round-trip through the URL parser', () {
      final coverPath = blogCoverObjectPath(
        posterId: 'u1',
        blogId: 'b1',
        version: '1730000000000',
        extension: '.jpg',
      );
      final url =
          'https://demo.supabase.co/storage/v1/object/public/'
          '$kBlogImagesBucket/$coverPath';
      expect(objectPathFromPublicUrl(url), coverPath);

      final avatarPath = avatarObjectPath(
        userId: 'u9',
        version: '1730000000001',
        extension: '.png',
      );
      final avatarUrl =
          'https://demo.supabase.co/storage/v1/object/public/'
          '$kAvatarsBucket/$avatarPath';
      expect(objectPathFromPublicUrl(avatarUrl), avatarPath);
    });
  });
}
