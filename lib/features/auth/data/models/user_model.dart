import '../../../../core/common/entities/user.dart';

class UserModel extends User {
  UserModel({
    required super.id,
    required super.email,
    required super.name,
    required super.updatedAt,
    super.avatarUrl = '',
    super.website = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      avatarUrl: map['avatar_url'] ?? '',
      website: map['website'] ?? '',
      updatedAt: map['updated_at'] == null
          ? DateTime.now()
          : DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'name': name,
      'avatar_url': avatarUrl,
      'website': website,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Columns safe to write from a profile edit.
  ///
  /// `email` is deliberately absent: the auth e-mail address only changes
  /// through Supabase Auth's update + confirmation flow, never through a
  /// direct `profiles` update.
  Map<String, dynamic> toProfileUpdateJson() {
    return <String, dynamic>{
      'name': name,
      'avatar_url': avatarUrl,
      'website': website,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? avatarUrl,
    String? website,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      website: website ?? this.website,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
