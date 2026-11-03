class User {
  final String id;
  final String email;
  final String name;
  final String avatarUrl;
  final String bio;
  final String website;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.updatedAt,
    this.avatarUrl = '',
    this.bio = '',
    this.website = '',
  });
}
