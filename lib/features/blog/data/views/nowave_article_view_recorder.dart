import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/views/article_view_recorder.dart';

/// The server deduplicates daily views and may decline to count the author's
/// own visit. Preparation captures the session, including the signed-out
/// generation, so a post-frame callback cannot attribute a prior page view to
/// an account that signed in while the frame was being built.
class NowaveArticleViewRecorder implements ArticleViewRecorder {
  const NowaveArticleViewRecorder({
    required this.client,
    required this.identity,
  });

  final NowaveApiClient client;
  final NowaveSessionIdentity identity;

  @override
  PreparedArticleView prepare(Blog article) {
    final generation = identity.sessionGeneration;
    final user = identity.activeUserId;
    final token = identity.accessToken;
    final fence =
        user != null && user.isNotEmpty && token != null && token.isNotEmpty
        ? NowaveSessionFence(userId: user, generation: generation)
        : null;
    return () async {
      if (identity.sessionGeneration != generation ||
          identity.activeUserId != user) {
        return;
      }
      if (fence != null && (identity.accessToken?.isEmpty ?? true)) return;
      await client.postViewOnce(
        '/articles/${article.id}/views',
        query: {'locale': article.locale},
        sessionFence: fence,
      );
    };
  }
}
