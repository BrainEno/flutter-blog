import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';

/// Only a hint for a private exact-edition read, never an authorization grant.
/// A slug, unknown locale, stale owner or incomplete session cannot address a
/// local recovery row. The server read still independently checks all fields.
StructuredBodyKey? structuredAuthoringKey({
  required Blog blog,
  required String signedInUserId,
  required NowaveSessionIdentity identity,
}) {
  final articleId = blog.authoringArticleId;
  if (blog.document == null ||
      signedInUserId.isEmpty ||
      signedInUserId != signedInUserId.trim() ||
      blog.posterId != signedInUserId ||
      identity.activeUserId != signedInUserId ||
      (identity.accessToken?.isEmpty ?? true) ||
      articleId == null ||
      articleId.isEmpty ||
      articleId != articleId.trim() ||
      !const {'zh-CN', 'zh-TW', 'en'}.contains(blog.locale)) {
    return null;
  }
  return StructuredBodyKey(
    userId: signedInUserId,
    articleId: articleId,
    locale: blog.locale,
  );
}
