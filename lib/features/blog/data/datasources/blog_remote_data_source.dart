// ignore_for_file: unnecessary_null_comparison

import 'dart:io';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/retry_on_connection_closed.dart';
import 'package:belog/core/utils/storage_objects.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart'
    show kBlogPageSize;
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class BlogRemoteDataSource {
  Future<BlogModel> uploadBlog(BlogModel blog);

  /// Uploads a cover to a fresh, versioned object path and returns its
  /// public URL. [mimeType] is sent as the object's contentType.
  Future<String> uploadBlogImage({
    required File image,
    required String blogId,
    required String posterId,
    String? mimeType,
  });

  /// Removes the cover object a public URL points at. Throws on failure;
  /// callers decide whether that is fatal or an orphan to log.
  Future<void> removeBlogImage(String publicUrl);

  Future<List<BlogModel>> getAllBlogs({required int page});
  Future<BlogModel> getBlogById(String blogId);
  Future<List<BlogModel>> getBlogsByPosterId(String posterId);
  Future<List<BlogModel>> getBlogsByTag(String tag);
  Future<List<BlogModel>> searchBlogs(String query);
  Future<BlogModel> editBlog(BlogModel blog);
  Future<bool> deleteBlog(String blogId);
  Future<List<BlogModel>> getUserLikedBlogs(String userId);
  Future<bool> toggleLikeBlog(String userId, String blogId);
  Future<bool> isBlogLikedByUser(String userId, String blogId);
}

/// Upper bound for search results so an unindexed title scan stays bounded.
const int kMaxSearchResults = 50;

class BlogRemoteDataSourceImpl implements BlogRemoteDataSource {
  final SupabaseClient supabaseClient;
  const BlogRemoteDataSourceImpl(this.supabaseClient);

  @override
  Future<BlogModel> uploadBlog(BlogModel blog) async {
    try {
      final blogData = await supabaseClient
          .from('blogs')
          .insert(blog.toJson())
          .select();
      return BlogModel.fromJson(blogData[0]);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<String> uploadBlogImage({
    required File image,
    required String blogId,
    required String posterId,
    String? mimeType,
  }) async {
    try {
      final path = blogCoverObjectPath(
        posterId: posterId,
        blogId: blogId,
        version: storageVersionNow(),
        extension: extensionForMime(mimeType),
      );
      await supabaseClient.storage
          .from(kBlogImagesBucket)
          .upload(
            path,
            image,
            fileOptions: FileOptions(
              // Explicit MIME so the object is served with the right
              // Content-Type (the picker already re-encoded the bytes).
              contentType: mimeType ?? 'image/jpeg',
              // Fresh versioned path: never overwrite in place.
              upsert: false,
            ),
          );
      return supabaseClient.storage.from(kBlogImagesBucket).getPublicUrl(path);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<void> removeBlogImage(String publicUrl) async {
    // Parses both legacy flat paths (path = blog id) and current nested
    // versioned paths, and ignores cache-busting query parameters.
    final path = objectPathFromPublicUrl(publicUrl);
    if (path == null) {
      AppLogger.debug('storage cleanup skipped: unrecognized object URL');
      return;
    }
    try {
      await supabaseClient.storage.from(kBlogImagesBucket).remove([path]);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getAllBlogs({required int page}) async {
    try {
      // Page size is shared with the feed bloc via kBlogPageSize.
      final from = (page - 1) * kBlogPageSize;
      final to = from + kBlogPageSize - 1;

      final query = supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .order('updated_at', ascending: false)
          .order('id', ascending: false)
          .range(from, to);

      final blogs = await retryOnConnectionClosed(() => query);

      return List<BlogModel>.from(
        blogs.map(
          (blog) => BlogModel.fromJson(blog).copyWith(
            posterName: blog['profiles']['name'],
            posterAvatar: blog['profiles']['avatar_url'],
          ),
        ),
      ).toList();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByPosterId(String posterId) async {
    try {
      final blogs = await supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .eq('poster_id', posterId)
          .order('updated_at', ascending: false)
          .order('id', ascending: false);

      return List<BlogModel>.from(
        blogs.map(
          (blog) => BlogModel.fromJson(blog).copyWith(
            posterName: blog['profiles']['name'],
            posterAvatar: blog['profiles']['avatar_url'],
          ),
        ),
      ).toList();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByTag(String tag) async {
    try {
      final blogs = await supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .contains('tags', tag)
          .order('updated_at', ascending: false)
          .order('id', ascending: false);

      return List<BlogModel>.from(
        blogs.map(
          (blog) => BlogModel.fromJson(blog).copyWith(
            posterName: blog['profiles']['name'],
            posterAvatar: blog['profiles']['avatar_url'],
          ),
        ),
      ).toList();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> searchBlogs(String query) async {
    try {
      // Clean and prepare the query
      final sanitizedQuery = query.trim();
      if (sanitizedQuery.isEmpty) {
        return [];
      }

      // Postgres treats %, _ and \ as LIKE wildcards/escapes. Escape them so
      // user input is matched literally; the pattern itself stays a substring
      // match around the query (works for Chinese text without pretending to
      // be full-text search).
      final escapedQuery = sanitizedQuery
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');

      // Search titles containing the query anywhere, newest first, with a
      // hard cap so an unindexed scan stays bounded. (.filter must come
      // before .order/.limit: the builder narrows to a transform builder.)
      final blogs = await supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .filter('title', 'ilike', '%$escapedQuery%')
          .order('updated_at', ascending: false)
          .order('id', ascending: false)
          .limit(kMaxSearchResults);

      // Map the results to BlogModel
      return blogs
          .map(
            (blog) => BlogModel.fromJson(blog).copyWith(
              posterName: blog['profiles']['name'],
              posterAvatar: blog['profiles']['avatar_url'],
            ),
          )
          .toList();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> deleteBlog(String blogId) async {
    try {
      final blog = await supabaseClient
          .from('blogs')
          .select('image_url')
          .eq('id', blogId)
          .single();

      final String imageUrl = (blog['image_url'] as String?) ?? '';

      // Delete the row first: once it is gone the cover object is
      // unreachable, so a storage failure must not fail the whole
      // operation and confuse the user with a "delete failed" for an
      // article that is already gone.
      await supabaseClient.from('blogs').delete().eq('id', blogId);

      if (imageUrl.isNotEmpty) {
        await _removeCoverQuietly(imageUrl);
      }
      return true;
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  /// Best-effort cover removal after the blog row is already deleted: a
  /// failure leaves an orphan, which is logged (with the object path, no
  /// personal data) so it can be swept later.
  Future<void> _removeCoverQuietly(String publicUrl) async {
    final path = objectPathFromPublicUrl(publicUrl);
    if (path == null) {
      return;
    }
    try {
      await supabaseClient.storage.from(kBlogImagesBucket).remove([path]);
    } catch (e, stackTrace) {
      AppLogger.error(
        'orphan cover left after blog delete (bucket-relative path: $path)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<BlogModel> editBlog(BlogModel blog) async {
    try {
      final blogUpdated = await supabaseClient
          .from('blogs')
          .update(blog.toJson())
          .eq('id', blog.id)
          .select()
          .single();

      return BlogModel.fromJson(blogUpdated);
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<BlogModel> getBlogById(String blogId) async {
    try {
      final res = await supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .eq('id', blogId)
          .single();

      return BlogModel.fromJson(res).copyWith(
        posterName: res['profiles']['name'],
        posterAvatar: res['profiles']['avatar_url'],
      );
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<List<BlogModel>> getUserLikedBlogs(String userId) async {
    try {
      final likedBlogs = await retryOnConnectionClosed(
        () => supabaseClient
            .from('likes')
            .select('blog_id, blogs(*, profiles (name, avatar_url))')
            .eq('user_id', userId)
            .order('updated_at', ascending: false, referencedTable: 'blogs'),
      );

      return List<BlogModel>.from(
        likedBlogs.map((like) {
          final blogData = like['blogs'] as Map<String, dynamic>;
          return BlogModel.fromJson(blogData).copyWith(
            posterName: blogData['profiles']['name'],
            posterAvatar: blogData['profiles']['avatar_url'],
          );
        }),
      ).toList();
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  /// Toggles the like and returns the like state AFTER the operation
  /// (true = liked). Unlike a read-then-write approach, deleting first and
  /// only inserting when nothing was deleted keeps concurrent toggles from
  /// double-flipping: every request reports the actual resulting server
  /// state, so the UI can reconcile against it.
  @override
  Future<bool> toggleLikeBlog(String userId, String blogId) async {
    try {
      // Delete the like if present. The returned rows tell whether one
      // existed, so the check and the write are a single server round trip.
      final deleted = await supabaseClient
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('blog_id', blogId)
          .select();

      if (deleted.isNotEmpty) {
        // A row was removed: the blog is now unliked.
        return false;
      }

      try {
        await supabaseClient.from('likes').insert({
          'user_id': userId,
          'blog_id': blogId,
        });
        return true;
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          // A concurrent toggle inserted the same row first (requires the
          // (user_id, blog_id) unique constraint): the blog is liked.
          return true;
        }
        rethrow;
      }
    } catch (e) {
      throw mapToServerException(e);
    }
  }

  @override
  Future<bool> isBlogLikedByUser(String userId, String blogId) async {
    try {
      final response = await supabaseClient
          .from('likes')
          .select()
          .eq('user_id', userId)
          .eq('blog_id', blogId)
          .maybeSingle();

      // Returns true if the like exists, false otherwise
      return response != null;
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST116') {
        // 404-like error when no results found
        return false;
      }
      throw mapToServerException(e);
    }
  }
}
