import 'package:belog/core/common/entities/user.dart';

class UserModel extends User {
  UserModel({
    required super.id,
    required super.email,
    required super.name,
    required super.updatedAt,
    super.avatarUrl = '',
    super.website = '',
  });

  /// Builds a model from a serialized no-wave profile
  /// (`GET /me/profile` / `GET /authors/:userId` / `PUT /me/profile`).
  ///
  /// The backend profile has no e-mail field; [email] comes from the
  /// locally cached sign-in e-mail.
  factory UserModel.fromNowaveProfile(
    Map<String, dynamic> map, {
    required String email,
  }) {
    return UserModel(
      id: map['userId'] as String? ?? '',
      email: email,
      name: map['displayName'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String? ?? '',
      website: map['websiteUrl'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
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
