import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:isar/isar.dart';

class BlogModel extends Blog {
  BlogModel(
      {required super.id,
      required super.title,
      required super.content,
      required super.posterId,
      required super.imageUrl,
      required super.tags,
      required super.updatedAt,
      super.posterName,
      super.posterAvatar,
      super.iid = Isar.autoIncrement});

  BlogModel copyWith({
    String? id,
    String? content,
    String? posterId,
    String? title,
    String? imageUrl,
    List<String>? tags,
    DateTime? updatedAt,
    String? posterName,
    String? posterAvatar,
  }) {
    return BlogModel(
      id: id ?? this.id,
      content: content ?? this.content,
      posterId: posterId ?? this.posterId,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
      posterName: posterName ?? this.posterName,
      posterAvatar: posterAvatar ?? this.posterAvatar,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'content': content,
      'poster_id': posterId,
      'image_url': imageUrl,
      'tags': tags,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory BlogModel.fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      throw Exception('Invalid blog data: json is null');
    }

    return BlogModel(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      posterId: map['poster_id'] as String,
      imageUrl: map['image_url'] as String,
      tags: List<String>.from(map['tags'] ?? []),
      updatedAt: map['updated_at'] == null
          ? DateTime.now()
          : DateTime.parse(map['updated_at'] as String),
    );
  }
}
