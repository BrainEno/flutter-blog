import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/entities/taxonomy_draft.dart';
import 'package:fpdart/fpdart.dart';

/// The character cap `POST /taxonomies` puts on a description; longer is a 400
/// server-side, so the counter on the screen and the check below quote the same
/// number the deployment enforces.
const int kTaxonomyDescriptionLimit = 2000;

/// The length cap the app's own reader puts on a slug (`TEXT` in the backend's
/// body normaliser, mirrored by `_isUsableSlug` where categories are parsed).
const int kTaxonomySlugLimit = 300;

/// Why this draft cannot be sent, or `null` when it can.
///
/// Deliberately narrower than a form validator. The only rules the backend
/// states for `name` and `slug` are "must be strings", so inventing a pattern
/// here would refuse shapes a deployment might well accept, and the editor
/// would be fighting the app instead of the server.
///
/// What this does refuse is what **this app** cannot read back. The catalogue
/// parser does not skip a row with a blank name or an unusable slug - it
/// throws for the whole page (`_parseCategory` in
/// `category_remote_data_source.dart`), so one such row would take category
/// browsing down for every reader, with no screen left to remove it from.
String? taxonomyDraftProblem(TaxonomyDraft draft) {
  if (draft.name.trim().isEmpty) return 'taxonomy.nameBlank';
  if (!_isReadableSlug(draft.slug)) return 'taxonomy.slugUnreadable';
  if (draft.description.length > kTaxonomyDescriptionLimit) {
    return 'taxonomy.descriptionTooLong';
  }
  return null;
}

/// Whether the app can put this slug in a URL and read the row back.
///
/// The same shape test the reader applies, kept here so a draft is judged
/// before it becomes somebody else's broken catalogue page.
bool _isReadableSlug(String value) =>
    value.isNotEmpty &&
    value.length <= kTaxonomySlugLimit &&
    value == value.trim() &&
    value != '.' &&
    value != '..';

/// What one taxonomy write ended as.
///
/// Both operations share this because both are decided the same way: the app
/// sends, and the server's answer - not a local guess - is what the screen
/// reports. `taxonomyDraftProblem` above is the only thing refused beforehand.
enum TaxonomyWrite {
  /// The server accepted it: `201` with a row this build could read, or a
  /// deletion receipt of `deleted: true`.
  done,

  /// `deleted: false`. The receipt says ownership failures are not
  /// distinguished from absence, so the screen may report "not removed" and
  /// nothing more precise than that.
  notRemoved,

  /// `403`: signed in, but this deployment does not treat the account as an
  /// editor. About the account, not the draft - retrying the same body will not
  /// change the answer.
  refused,

  /// `404`/`405` on the route: this deployment has no taxonomy administration
  /// to use. A row that is simply gone answers `deleted: false` instead.
  unavailable,

  /// A `2xx` this build could not read, so the write may have landed anyway.
  /// The screen re-reads the catalogue and never resends: a second create would
  /// put a duplicate in the public catalogue, and there is no conditional write
  /// to make it safe. Offline is not reported here - both writes refuse an
  /// attempt while the device has no connection, before any request exists.
  unknown,
}

/// Reading the catalogue and maintaining it, for editors only.
///
/// The catalogue read is not a second implementation of `/categories`: it goes
/// through [CategoryRepository], the path readers already use. One page of that
/// catalogue is what this screen can see, which is why the screen has to say so
/// rather than present the list as the whole catalogue.
abstract interface class TaxonomyAdminRepository {
  /// The catalogue for the current content locale, in the server's order.
  ///
  /// A row whose `id` is empty came from an older response; it can be shown but
  /// not removed, and [remove] refuses such an id rather than guessing.
  Future<Either<Failure, List<CategoryRef>>> catalogue();

  /// One create, sent as `{kind, slug, name, description}` and nothing else:
  /// the backend treats an extra key as a bad request for the whole body.
  ///
  /// `locale` is left out on purpose. The route accepts only `zh-CN` today, and
  /// naming that here would pin a client to a server-side constant while the
  /// omission lets a future deployment decide.
  Future<Either<Failure, TaxonomyWrite>> create({
    required NowaveSessionFence fence,
    required TaxonomyDraft draft,
  });

  /// One row removed by its id, which must be the UUID the catalogue carried.
  Future<Either<Failure, TaxonomyWrite>> remove({
    required NowaveSessionFence fence,
    required String id,
  });
}
