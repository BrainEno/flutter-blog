import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:isar_community/isar.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';

abstract interface class BlogLocalDataSource {
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs});
  Future<List<BlogModel>> loadBlogs();
  Future<List<BlogModel>> searchLocalBlogs(String query);
}

class BlogLocalDataSourceImpl implements BlogLocalDataSource {
  final Isar isar;

  BlogLocalDataSourceImpl({required this.isar});

  IsarCollection<Blog> get blogCollection => isar.blogs;

  @override
  Future<List<BlogModel>> loadBlogs() async {
    List<BlogModel> blogs = [];

    int len = blogCollection.countSync();

    for (int i = 0; i < len; i++) {
      final blog = await blogCollection.get(i);
      if (blog != null) {
        blogs.add(BlogModel(
            id: blog.id,
            title: blog.title,
            content: blog.content,
            posterId: blog.posterId,
            imageUrl: blog.imageUrl,
            tags: blog.tags,
            updatedAt: blog.updatedAt));
      }
    }

    return blogs;
  }

  @override
  Future<void> uploadLocalBlogs({required List<BlogModel> blogs}) async {
    await isar.writeTxn(() async {
      blogCollection.putAll(blogs);
    });
  }

  @override
  Future<List<BlogModel>> searchLocalBlogs(String query) async {
    final blogs = await blogCollection
        .filter()
        .titleContains(query, caseSensitive: false)
        .findAll()
        .then((value) => value
            .map((e) => BlogModel(
                id: e.id,
                title: e.title,
                content: e.content,
                posterId: e.posterId,
                imageUrl: e.imageUrl,
                tags: e.tags,
                updatedAt: e.updatedAt))
            .toList());

    return blogs;
  }
}
