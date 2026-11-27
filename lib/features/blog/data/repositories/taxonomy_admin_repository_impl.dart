import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/entities/taxonomy_draft.dart';
import 'package:belog/features/blog/domain/repositories/category_repository.dart';
import 'package:belog/features/blog/domain/repositories/taxonomy_admin_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The catalogue and the two admin writes of #381, against
/// `GET /categories`, `POST /taxonomies` and `DELETE /taxonomies/:id`.
///
/// Nothing here is cached or queued. A cached catalogue would let an editor
/// "delete" a row another editor already recreated, and an outbox entry for a
/// create would happily produce the duplicate the server was refusing.
class TaxonomyAdminRepositoryImpl implements TaxonomyAdminRepository {
  const TaxonomyAdminRepositoryImpl({
    required this.categories,
    required this.client,
    required this.connectionChecker,
  });

  /// The read path readers already use, so the catalogue this screen shows is
  /// parsed by exactly one implementation - including its one-page limit.
  final CategoryRepository categories;
  final NowaveApiClient client;
  final ConnectionChecker connectionChecker;

  @override
  Future<Either<Failure, List<CategoryRef>>> catalogue() =>
      categories.listCategories();

  @override
  Future<Either<Failure, TaxonomyWrite>> create({
    required NowaveSessionFence fence,
    required TaxonomyDraft draft,
  }) async {
    final problem = taxonomyDraftProblem(draft);
    if (problem != null) {
      return left(
        Failure(
          '这一条应用自己读不回来，所以没有发送',
          kind: FailureKind.validation,
          code: problem,
        ),
      );
    }
    // Before the fence call, like the shelf save: offline is a fact the app can
    // state without spending a request, and it is the one case where "it may
    // have landed anyway" would be false.
    if (!await connectionChecker.isConnected) {
      return left(Failure.networkOffline());
    }
    try {
      // Exactly these four keys. `POST /taxonomies` refuses the whole body when
      // it sees a key outside its list, so a field added for convenience - an
      // `id`, a `locale`, a `kind: tag` - turns into a 400 about the request
      // rather than about the draft.
      final data = await client.postJsonForViewerOnce(
        '/taxonomies',
        {
          'kind': 'category',
          'slug': draft.slug,
          'name': draft.name,
          'description': draft.description,
        },
        expectedUserId: fence.userId,
        expectedSessionGeneration: fence.generation,
      );
      if (!_isStoredRow(data)) {
        return const Right(TaxonomyWrite.unknown);
      }
      return const Right(TaxonomyWrite.done);
    } catch (error) {
      return _outcomeOf(error);
    }
  }

  @override
  Future<Either<Failure, TaxonomyWrite>> remove({
    required NowaveSessionFence fence,
    required String id,
  }) async {
    final wanted = id.trim();
    if (wanted.isEmpty) {
      // `CategoryRef.id` documents an empty value as "unknown": an older
      // response, or a hand-built row. Deleting needs the UUID the catalogue
      // carried, and guessing one is how somebody else's category disappears.
      return left(
        const Failure(
          '这一行没有可用于删除的编号',
          kind: FailureKind.validation,
          code: 'taxonomy.idUnknown',
        ),
      );
    }
    if (!await connectionChecker.isConnected) {
      return left(Failure.networkOffline());
    }
    try {
      final data = await client.deleteJson(
        '/taxonomies/${Uri.encodeComponent(wanted)}',
        sessionFence: fence,
        // A redirect would resend the delete to another origin, where the row
        // may already be gone.
        followRedirects: false,
      );
      final deleted = data is Map<String, dynamic> ? data['deleted'] : null;
      if (deleted is! bool) {
        // A 2xx that does not answer with a boolean has not said anything, and
        // "no receipt" must not be rendered as either success or absence.
        return const Right(TaxonomyWrite.unknown);
      }
      return right(
        deleted ? TaxonomyWrite.done : TaxonomyWrite.notRemoved,
      );
    } catch (error) {
      return _outcomeOf(error);
    }
  }

  /// Status answers that are facts about the deployment or the account, and
  /// the classification every other throw already has.
  ///
  /// The backend's message text is English and can carry detail, so it is
  /// classified through `mapErrorToFailure` and never shown: a 409 says
  /// "already in the catalogue" via `server.CONFLICT`, and a 400 the app
  /// should not have sent says so via `server.BAD_USER_INPUT`.
  Either<Failure, TaxonomyWrite> _outcomeOf(Object error) {
    if (error is NowaveApiException) {
      if (error.statusCode == 403) {
        return const Right(TaxonomyWrite.refused);
      }
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const Right(TaxonomyWrite.unavailable);
      }
      if (error.code == 'SESSION_CHANGED') {
        return left(
          const Failure(
            '账号已经变化，这次修改没有发送',
            kind: FailureKind.auth,
            code: 'auth.sessionChanged',
          ),
        );
      }
    }
    return left(mapErrorToFailure(error).forPresentation());
  }

  /// The row `POST /taxonomies` answers with: `{id, kind, slug, name, ...}`.
  ///
  /// The id matters most - it is the only thing that can remove the row again -
  /// so a create that cannot name its own result is `unknown`, not `done`.
  static bool _isStoredRow(dynamic data) {
    if (data is! Map<String, dynamic>) return false;
    final id = data['id'];
    return id is String &&
        id.trim().isNotEmpty &&
        data['slug'] is String &&
        data['name'] is String;
  }
}
