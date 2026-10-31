import 'package:belog/features/blog/domain/entities/blog.dart';

/// The source of a feed page. Cached articles may be stale or incomplete.
enum BlogFeedSource { network, cache }

/// A feed page and the source used to fetch it.
///
/// All pages in one scrolling session must use the same source. A refresh
/// starts a new session and chooses a source again.
class BlogFeedPage {
  const BlogFeedPage({required this.blogs, required this.source});

  final List<Blog> blogs;
  final BlogFeedSource source;
}
