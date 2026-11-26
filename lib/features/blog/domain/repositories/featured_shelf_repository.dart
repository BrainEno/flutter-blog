import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/featured_shelf_entry.dart';
import 'package:fpdart/fpdart.dart';

/// How many works the shelf holds. The server refuses a longer list outright
/// (`MAX_FEATURED_ARTICLES`), so this is a ceiling, not a suggestion.
const int kFeaturedShelfCapacity = 20;

/// Why this list cannot be sent, or `null` when it can.
///
/// Both the screen and the repository call this. The screen calls it to say
/// "you cannot save yet" while the editor is still typing; the repository calls
/// it before touching the network so a caller that skipped the check never
/// spends a request on a body the server was always going to refuse. The
/// server checks the same two things - length and duplicates - and refuses the
/// whole write rather than applying part of it.
String? featuredShelfProblem(List<String> articleIds) {
  if (articleIds.length > kFeaturedShelfCapacity) return 'featured.tooMany';
  if (articleIds.toSet().length != articleIds.length) {
    return 'featured.duplicate';
  }
  return null;
}

/// What a save attempt ended as.
enum FeaturedShelfSave {
  /// The server stored the list; [FeaturedShelfSaveResult.storedIds] is what it
  /// says is on the shelf now.
  stored,

  /// `403`: the account is signed in but this deployment does not treat it as
  /// an editor. Not a failure to retry - the answer is about the account.
  refused,

  /// `404`/`405`: this deployment has no editorial shelf to arrange.
  unavailable,

  /// A `2xx` this build could not read. The write may have landed, so the
  /// screen must re-read rather than resend: this is a whole-list replace, and
  /// a second send would overwrite whatever a later editor saved in between.
  /// A transport problem is not reported here - `save` refuses an offline
  /// attempt before the body exists, so "unknown" never means "probably lost".
  unknown,
}

/// The outcome of one save, with the shelf as the server stored it.
class FeaturedShelfSaveResult {
  const FeaturedShelfSaveResult(this.outcome, {this.storedIds = const []});

  const FeaturedShelfSaveResult.refused()
    : outcome = FeaturedShelfSave.refused,
      storedIds = const [];

  const FeaturedShelfSaveResult.unavailable()
    : outcome = FeaturedShelfSave.unavailable,
      storedIds = const [];

  const FeaturedShelfSaveResult.unknown()
    : outcome = FeaturedShelfSave.unknown,
      storedIds = const [];

  final FeaturedShelfSave outcome;
  final List<String> storedIds;
}

/// Reading and arranging the editorial shelf for one content locale.
///
/// Its own repository, for the reason `AccountSessionRepository` gives: a
/// screen can hold two narrow calls without pulling the whole article contract
/// - caching, drafts, the offline queue - into its test double. And the shelf
/// genuinely is separate data: the lists an editor browses are paged at ten,
/// while the shelf holds twenty, so reading it through the feed path would show
/// half of it and save that half back.
abstract interface class FeaturedShelfRepository {
  /// The shelf as stored, in editorial order, for [locale].
  ///
  /// A deployment with no curated shelf answers with the server's own default
  /// ranking, and nothing in the response says which of the two it was. That
  /// is why the screen states the possibility instead of claiming these are
  /// somebody's picks.
  Future<Either<Failure, List<FeaturedShelfEntry>>> load({
    required String locale,
  });

  /// Works the editor could add, newest first; with a [query], the server's own
  /// search over title, summary and text blocks. Only published works appear,
  /// which is the server's rule, not a filter here.
  Future<Either<Failure, List<FeaturedShelfEntry>>> browse({
    required String locale,
    String query = '',
  });

  /// Replaces the whole shelf for [locale] in one write.
  ///
  /// Fenced to [fence]: the account and generation that opened the screen must
  /// still be the active ones when the body goes out and when the response
  /// comes back, and the request is never replayed after a 401.
  Future<Either<Failure, FeaturedShelfSaveResult>> save({
    required NowaveSessionFence fence,
    required String locale,
    required List<String> articleIds,
  });
}
