import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';

/// Identity of an existing server article's language edition, owned by one
/// account. The backend namespace is supplied independently by the store.
/// A public slug is not an article ID and must not be used here.
class StructuredBodyKey {
  StructuredBodyKey({
    required this.userId,
    required this.articleId,
    required this.locale,
  }) {
    _requiredIdentity(userId, 'userId');
    _requiredIdentity(articleId, 'articleId');
    if (!const {'zh-CN', 'zh-TW', 'en'}.contains(locale)) {
      throw ArgumentError.value(locale, 'locale', 'Unknown article edition');
    }
  }

  final String userId;
  final String articleId;
  final String locale;

  static void _requiredIdentity(String value, String name) {
    if (value.isEmpty || value.trim() != value) {
      throw ArgumentError.value(
        value,
        name,
        'A nonempty exact identity is required',
      );
    }
  }
}

/// A saved body, plus the exact server body it was originally based on.
///
/// This records only the structured body, not a complete editor session:
/// title, summary, tags, categories, cover selection and publication status
/// still need their own recovery design. A comparison of [base] with a fresh
/// server body may detect some changes, but is not an atomic remote write.
/// [rowId] and [revision] are local compare-and-swap tokens only.
class StructuredBodyRecovery {
  const StructuredBodyRecovery({
    required this.key,
    required this.backendStorageKey,
    required this.rowId,
    required this.revision,
    required this.base,
    required this.body,
    required this.updatedAt,
    required this.baseStorageJson,
    required this.bodyStorageJson,
  });

  final StructuredBodyKey key;

  /// Store namespace captured at load time, with credentials stripped.
  final String backendStorageKey;
  final int rowId;
  final int revision;
  final StructuredArticleDraft base;
  final StructuredArticleDraft body;
  final DateTime updatedAt;

  /// Opaque exact storage bytes, used to conservatively detect modifications
  /// that did not advance the local revision (including damaged rows).
  /// Never use these strings as a remote request or as an authorization token.
  final String baseStorageJson;
  final String bodyStorageJson;
}
