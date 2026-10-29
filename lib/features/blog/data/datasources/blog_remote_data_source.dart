// ignore_for_file: unnecessary_null_comparison

import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/utils/retry_on_connection_closed.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class BlogRemoteDataSource {
  Future<BlogModel> uploadBlog(BlogModel blog);
  Future<String> uploadBlogImage({
    required File image,
    required BlogModel blog,
  });
  Future<String> uploadAvatarImage({
    required File image,
    required String userId,
  });
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
      throw ServerException(e.toString());
    }
  }

  @override
  Future<String> uploadBlogImage({
    required File image,
    required BlogModel blog,
  }) async {
    try {
      await supabaseClient.storage
          .from('blog_images')
          .upload(blog.id, image, fileOptions: FileOptions(upsert: true));
      return supabaseClient.storage.from('blog_images').getPublicUrl(blog.id);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<BlogModel>> getAllBlogs({required int page}) async {
    try {
      const pageSize = 10; // Define how many blogs per page
      final from = (page - 1) * pageSize;
      final to = from + pageSize - 1;

      final query = supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
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
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByPosterId(String posterId) async {
    try {
      final blogs = await supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .eq('poster_id', posterId);

      return List<BlogModel>.from(
        blogs.map(
          (blog) => BlogModel.fromJson(blog).copyWith(
            posterName: blog['profiles']['name'],
            posterAvatar: blog['profiles']['avatar_url'],
          ),
        ),
      ).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<BlogModel>> getBlogsByTag(String tag) async {
    try {
      final blogs = await supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)')
          .contains('tags', tag);

      return List<BlogModel>.from(
        blogs.map(
          (blog) => BlogModel.fromJson(blog).copyWith(
            posterName: blog['profiles']['name'],
            posterAvatar: blog['profiles']['avatar_url'],
          ),
        ),
      ).toList();
    } catch (e) {
      throw ServerException(e.toString());
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

      // Set up the base query
      final blogsQuery = supabaseClient
          .from('blogs')
          .select('*, profiles (name, avatar_url)');

      // Search titles containing the query anywhere
      final blogs = await blogsQuery.filter(
        'title',
        'ilike',
        '%$sanitizedQuery%',
      );

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
      throw ServerException(e.toString());
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

      final String imageUrl = blog['image_url'];

      await supabaseClient.from('blogs').delete().eq('id', blogId);

      if (imageUrl.isNotEmpty) {
        final int index = imageUrl.lastIndexOf('/');
        final String path = imageUrl.substring(index + 1);
        print(path);
        await supabaseClient.storage.from('blog_images').remove([
          "blog_images/$path",
        ]);
      }
      return true;
    } catch (e) {
      throw ServerException(e.toString());
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
      throw ServerException(e.toString());
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
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<BlogModel>> getUserLikedBlogs(String userId) async {
    try {
      final likedBlogs = await retryOnConnectionClosed(
        () => supabaseClient
            .from('likes')
            .select('blog_id, blogs(*, profiles (name, avatar_url))')
            .eq('user_id', userId),
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
      throw ServerException(e.toString());
    }
  }

  @override
  Future<bool> toggleLikeBlog(String userId, String blogId) async {
    try {
      // Check if the like already exists
      final existingLike = await isBlogLikedByUser(userId, blogId);

      if (!existingLike) {
        // Add like
        await supabaseClient.from('likes').insert({
          'user_id': userId,
          'blog_id': blogId,
        });
      } else {
        // Remove like
        await supabaseClient
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('blog_id', blogId);
      }
      return true;
    } catch (e) {
      throw ServerException(e.toString());
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
      throw ServerException(e.toString());
    }
  }

  @override
  Future<String> uploadAvatarImage({
    required File image,
    required String userId,
  }) async {
    try {
      await supabaseClient.storage
          .from('avatars')
          .upload(userId, image, fileOptions: FileOptions(upsert: true));
      return supabaseClient.storage.from('avatars').getPublicUrl(userId);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
