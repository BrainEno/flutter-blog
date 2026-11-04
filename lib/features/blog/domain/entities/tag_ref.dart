/// A tag as the server knows it: the display name an article stores plus the
/// opaque URL slug the taxonomy routes address it by.
///
/// The slug is server-generated (`normalizeHashtag` derives an ASCII stem plus
/// a hash suffix) and cannot be computed on the client, so it has to be looked
/// up rather than derived from [name].
class TagRef {
  const TagRef({required this.name, required this.slug});

  final String name;
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is TagRef && other.name == name && other.slug == slug;

  @override
  int get hashCode => Object.hash(name, slug);

  @override
  String toString() => 'TagRef($name, $slug)';
}
