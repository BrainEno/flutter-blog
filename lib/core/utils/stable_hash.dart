import 'dart:convert';

/// A stable 32-bit FNV-1a hash of [value]'s UTF-8 bytes.
///
/// Stable means the same number on every device, in every Dart release, for the
/// life of this app: the cover a reader sees for an article must not change
/// because they upgraded, or because a second device hashed it differently.
/// `String.hashCode` makes no such promise - it may be re-seeded per process
/// and has changed between Dart versions - and `Random()` would hand an article
/// a new plate on every rebuild.
///
/// FNV-1a is chosen for being six lines, thoroughly documented and good enough
/// for picking one of four. The known-answer vectors in
/// `test/unit/core/stable_hash_test.dart` pin the implementation to the
/// published ones, so a well-meant "cleanup" cannot quietly change every cover
/// in the app.
int stableHash32(String value) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
