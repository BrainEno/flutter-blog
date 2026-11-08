import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart'
    show kPopularFeedMaxOffset;

/// How many articles one page of an author's list holds.
///
/// The API caps `limit` at 100 and defaults this route to 20. A page that comes
/// back shorter than this is the end of the list - the only "has more" signal
/// `/authors/:id/articles` offers.
const int kAuthorPageSize = 20;

/// How deep the most-saved order of an author's list can be read.
///
/// The bound is the same server constant as the home feed's popular order
/// (`MAX_ARTICLE_OFFSET_POPULAR`): re-ranked while it is read, so a deep page
/// can only be refused. Aliased rather than repeated, so the two cannot drift.
const int kAuthorPopularMaxOffset = kPopularFeedMaxOffset;
