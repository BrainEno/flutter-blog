import 'dart:typed_data';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_plan.dart';
import 'package:fpdart/fpdart.dart';

class NotionImportRepositoryImpl implements NotionImportRepository {
  const NotionImportRepositoryImpl(this.client);
  final NowaveApiClient client;

  @override
  Future<Either<Failure, NotionImportReport>> submit({
    required NotionBundle bundle,
    required bool apply,
    required NowaveSessionFence sessionFence,
    NotionImportPlan? plan,
  }) async {
    try {
      final token = apply
          ? plan?.consume(bundle: bundle, fence: sessionFence)
          : null;
      if (apply && token == null) throw const NotionImportPlanFormatException();
      final data = await client.postJsonForViewerOnce(
        '/imports/notion',
        {'bundle': bundle.json, 'apply': apply, if (apply) 'planToken': token},
        expectedUserId: sessionFence.userId,
        expectedSessionGeneration: sessionFence.generation,
        timeout: NowaveApiClient.notionImportTimeout,
      );
      return right(_report(data, apply, bundle, sessionFence));
    } on NotionImportPlanFormatException {
      return left(
        const Failure(
          '导入预览无效或已过期，请重新预览',
          kind: FailureKind.validation,
          code: 'notion.planInvalid',
        ),
      );
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  @override
  Future<Either<Failure, String>> uploadImage({
    required Uint8List bytes,
    required String contentType,
    required NowaveSessionFence sessionFence,
  }) async {
    try {
      // Never retried here: a lost response does not prove the upload
      // failed, and media has no idempotency key.
      final asset = await client.uploadMedia(
        bytes,
        contentType,
        sessionFence: sessionFence,
      );
      return right(client.mediaUri(asset.id).toString());
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  NotionImportReport _report(
    dynamic data,
    bool apply,
    NotionBundle bundle,
    NowaveSessionFence fence,
  ) {
    final expectedPages = bundle.pageCount;
    if (data is! Map<String, dynamic> ||
        data['applied'] != apply ||
        data['pages'] is! List ||
        (data['pages'] as List).length > expectedPages) {
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
    return NotionImportReport(
      applied: apply,
      pages: List.unmodifiable(pages),
      omittedPages: expectedPages - pages.length,
      plan: apply
          ? null
          : NotionImportPlan.fromPreview(
              bundle: bundle,
              fence: fence,
              token: data['planToken'],
              expiresAt: data['planExpiresAt'],
            ),
    );
  }
}
