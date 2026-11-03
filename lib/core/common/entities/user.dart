class User {
  final String id;
  final String email;
  final String name;

  /// Public author introduction (no-wave profile `bio`, up to 5000 chars).
  ///
  /// It is sent with every profile write: the backend defaults a missing
  /// `bio` to an empty string, so omitting it would erase the author's
  /// introduction whenever any other field is saved.
  final String bio;
  final String avatarUrl;
  final String website;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.updatedAt,
    this.bio = "",
    this.avatarUrl = "",
    this.website = "",
  });
}
