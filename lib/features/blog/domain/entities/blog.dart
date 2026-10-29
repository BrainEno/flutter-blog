import 'package:isar/isar.dart';

part 'blog.g.dart';

@Collection()
class Blog {
  final Id iid;
  final String id;
  final String title;
  final String content;
  final String posterId;
  final String imageUrl;
  final List<String> tags;
  final DateTime updatedAt;
  final String? posterName;
  final String? posterAvatar;
  @Index()
  List<String> get titleWords => title.split(' ');

  Blog(
      {required this.iid,
      required this.id,
      required this.title,
      required this.content,
      required this.posterId,
      required this.imageUrl,
      required this.tags,
      required this.updatedAt,
      this.posterName,
      this.posterAvatar});
}
