import 'package:belog/features/blog/domain/entities/blog.dart';

/// Deferred view operation: preparation captures the viewer at render time,
/// while the actual network call is delayed until the page has painted.
typedef PreparedArticleView = Future<void> Function();

abstract interface class ArticleViewRecorder {
  PreparedArticleView prepare(Blog article);
}

/// Prepares best-effort reader telemetry. Unknown cache editions are skipped
/// rather than silently attributing a view to a guessed content language.
class RecordArticleView {
  const RecordArticleView(this.recorder);
  final ArticleViewRecorder recorder;

  PreparedArticleView? prepare(Blog article) {
    if (article.isDraft ||
        !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(article.id) ||
        !const {'zh-CN', 'zh-TW', 'en'}.contains(article.locale)) {
      return null;
    }
    return recorder.prepare(article);
  }
}
