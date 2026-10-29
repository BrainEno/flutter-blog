import 'package:isar_community/isar.dart';

part 'blog.g.dart';

/// Legacy Isar collection that mirrors the schema shipped in older app
/// versions.
///
/// It exists only so [AppDatabase.importLegacyIfNeeded] can read databases
/// written before the SQLite migration. The class name, property names,
/// property ids and indexes must stay exactly as the old generator produced
/// them: Isar identifies collections by these values and any drift would make
/// existing local data unreadable. Do not use this class for new features; the
/// live store is Drift/SQLite and the domain entity stays persistence-free.
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

  Blog({
    required this.iid,
    required this.id,
    required this.title,
    required this.content,
    required this.posterId,
    required this.imageUrl,
    required this.tags,
    required this.updatedAt,
    this.posterName,
    this.posterAvatar,
  });
}
