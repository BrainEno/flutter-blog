import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:fpdart/fpdart.dart';

class NotionImportRepositoryImpl implements NotionImportRepository {
  const NotionImportRepositoryImpl(this.client);
  final NowaveApiClient client;

  @override
  Future<Either<Failure, NotionImportReport>> submit({
    required NotionBundle bundle,
    required bool apply,
    required NowaveSessionFence sessionFence,
  }) async {
    try {
      final data = await client.postJsonForViewerOnce(
        '/imports/notion',
        {'bundle': bundle.json, 'apply': apply},
        expectedUserId: sessionFence.userId,
        expectedSessionGeneration: sessionFence.generation,
        timeout: const Duration(minutes: 2),
      );
      return right(_report(data, apply, (bundle.json['pages'] as List).length));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  NotionImportReport _report(dynamic data, bool apply, int expectedPages) {
    if (data is! Map<String, dynamic> ||
        data['applied'] != apply ||
        data['pages'] is! List ||
        (data['pages'] as List).length != expectedPages) {
      throw const FormatException('Invalid import report');
    }
    final pages = <NotionImportPage>[];
    for (final raw in data['pages'] as List) {
      if (raw is! Map<String, dynamic> ||
          raw['title'] is! String ||
          raw['locale'] is! String ||
          raw['detail'] is! String ||
          raw['externalId'] is! String ||
          raw['slug'] is! String ||
          (raw['articleId'] != null && raw['articleId'] is! String) ||
          raw['issues'] is! List) {
        throw const FormatException('Invalid import page report');
      }
      final action = switch (raw['action']) {
        'create' => NotionImportAction.create,
        'update' => NotionImportAction.update,
        'skip' => NotionImportAction.skip,
        'refused' => NotionImportAction.refused,
        'failed' => NotionImportAction.failed,
        _ => throw const FormatException('Invalid import action'),
      };
      final issues = <NotionImportIssue>[];
      for (final issue in raw['issues'] as List) {
        if (issue is! Map<String, dynamic> ||
            issue['code'] is! String ||
            issue['detail'] is! String) {
          throw const FormatException('Invalid import issue');
        }
        issues.add(
          NotionImportIssue(
            code: issue['code'] as String,
            detail: issue['detail'] as String,
          ),
        );
      }
      pages.add(
        NotionImportPage(
          title: raw['title'] as String,
          locale: raw['locale'] as String,
          action: action,
          externalId: raw['externalId'] as String,
          slug: raw['slug'] as String,
          articleId: raw['articleId'] as String?,
          detail: raw['detail'] as String,
          issues: List.unmodifiable(issues),
        ),
      );
    }
    return NotionImportReport(applied: apply, pages: List.unmodifiable(pages));
  }
}
