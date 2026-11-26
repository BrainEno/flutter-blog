import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/data/datasources/article_payload.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/featured_shelf_entry.dart';
import 'package:belog/features/blog/domain/repositories/featured_shelf_repository.dart';
import 'package:fpdart/fpdart.dart';

/// Reads and arranges `GET|PUT /featured` for one content locale.
///
/// The shelf is not cached and not queued. Both would be lies: a cached shelf
/// is last week's editorial decision, and an outbox entry for a whole-list
/// replace would resend an ordering that a later editor already overwrote.
class FeaturedShelfRepositoryImpl implements FeaturedShelfRepository {
  const FeaturedShelfRepositoryImpl({
    required this.client,
    required this.connectionChecker,
  });

  final NowaveApiClient client;
  final ConnectionChecker connectionChecker;

  @override
  Future<Either<Failure, List<FeaturedShelfEntry>>> load({
    required String locale,
  }) {
    return _read(
      path: '/featured',
      // `limit` is the server's own default today; naming it is what keeps
      // this read from becoming the ten-row feed page and then saving ten rows
      // back as the whole shelf.
      query: {
        'limit': '$kFeaturedShelfCapacity',
        'offset': '0',
        'locale': locale,
      },
    );
  }

  @override
  Future<Either<Failure, List<FeaturedShelfEntry>>> browse({
    required String locale,
    String query = '',
  }) {
    final text = query.trim();
    return _read(
      path: '/articles',
      query: {
        'limit': '$kFeaturedShelfCapacity',
        'offset': '0',
        'locale': locale,
        if (text.isNotEmpty) 'query': text,
      },
    );
  }

  @override
  Future<Either<Failure, FeaturedShelfSaveResult>> save({
    required NowaveSessionFence fence,
    required String locale,
    required List<String> articleIds,
  }) async {
    final problem = featuredShelfProblem(articleIds);
    if (problem != null) {
      return left(
        Failure('这份精选书架还不能发送', kind: FailureKind.validation, code: problem),
      );
    }
    // Checked before the fence call rather than after: offline is a fact the
    // app can state without spending a request, and it is the one case where
    // "the write may have landed" would be false.
    if (!await connectionChecker.isConnected) {
      return left(Failure.networkOffline());
    }
    try {
      final data = await client.putJsonForViewerOnce(
        '/featured',
        {'articleIds': articleIds},
        expectedUserId: fence.userId,
        expectedSessionGeneration: fence.generation,
        query: {'locale': locale},
      );
      final entries = _entriesOf(data);
      if (entries == null) {
        // A 2xx this build cannot read may still have replaced the shelf. The
        // screen re-reads instead of resending.
        return const Right(FeaturedShelfSaveResult.unknown());
      }
      return right(
        FeaturedShelfSaveResult(
          FeaturedShelfSave.stored,
          storedIds: [for (final entry in entries) entry.articleId],
        ),
      );
    } on NowaveApiException catch (error) {
      if (error.statusCode == 403) {
        return const Right(FeaturedShelfSaveResult.refused());
      }
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const Right(FeaturedShelfSaveResult.unavailable());
      }
      if (error.code == 'SESSION_CHANGED') {
        return left(
          const Failure(
            '账号已经变化，这次保存没有发送',
            kind: FailureKind.auth,
            code: 'auth.sessionChanged',
          ),
        );
      }
      return left(mapErrorToFailure(error).forPresentation());
    } catch (error) {
      return left(mapErrorToFailure(error).forPresentation());
    }
  }

  Future<Either<Failure, List<FeaturedShelfEntry>>> _read({
    required String path,
    required Map<String, String> query,
  }) async {
    try {
      final data = await client.getJson(path, query: query);
      final entries = _entriesOf(data);
      if (entries == null) return left(_unreadableShelf);
      return right(entries);
    } catch (error) {
      return left(mapErrorToFailure(error).forPresentation());
    }
  }

  /// Rows in shelf order, or null when the payload is not a list this build can
  /// name an article from.
  ///
  /// A missing work id is not filtered out: a shelf the app cannot send back
  /// unchanged is exactly the half-applied write the server refuses, and a
  /// silently shortened list is how a curation screen loses somebody's pick.
  static List<FeaturedShelfEntry>? _entriesOf(dynamic data) {
    final List<BlogModel> rows;
    try {
      rows = articlePayloadList(data);
    } catch (_) {
      return null;
    }
    final entries = <FeaturedShelfEntry>[];
    for (final row in rows) {
      final articleId = row.authoringArticleId;
      if (articleId == null) return null;
      entries.add(
        FeaturedShelfEntry(
          articleId: articleId,
          slug: row.id,
          title: row.title,
        ),
      );
    }
    return entries;
  }

  static const Failure _unreadableShelf = Failure(
    '服务器返回的精选书架无法读取',
    kind: FailureKind.server,
    code: 'featured.unreadable',
  );
}
