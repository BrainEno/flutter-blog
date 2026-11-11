import 'dart:convert';

import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:fpdart/fpdart.dart';

class NotionExportRepositoryImpl implements NotionExportRepository {
  const NotionExportRepositoryImpl(this.client);
  final NowaveApiClient client;

  @override
  Future<Either<Failure, NotionExportResult>> export({
    required String slug,
    required NowaveSessionFence sessionFence,
  }) async {
    try {
      if (slug.isEmpty || slug.trim() != slug || slug.contains(',')) {
        throw const FormatException('Invalid work address');
      }
      final data = await client.getJson(
        '/imports/notion/export',
        query: {'slugs': slug},
        sessionFence: sessionFence,
        followRedirects: false,
      );
      return right(_parse(data, slug));
    } catch (error) {
      return left(mapErrorToFailure(error));
    }
  }

  NotionExportResult _parse(dynamic data, String slug) {
    if (data is! Map<String, dynamic> ||
        data['bundle'] is! Map<String, dynamic> ||
        data['report'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid export response');
    }
    final bundle = data['bundle'] as Map<String, dynamic>;
    final report = data['report'] as Map<String, dynamic>;
    if (bundle['version'] != 1 ||
        bundle['pages'] is! List ||
        report['works'] is! List ||
        report['missing'] is! List) {
      throw const FormatException('Invalid export response');
    }
    final pages = bundle['pages'] as List;
    final works = report['works'] as List;
    final missing = report['missing'] as List;
    if (pages.length > 200 ||
        works.length > 1 ||
        missing.length > 1 ||
        (works.isEmpty &&
            (missing.length != 1 ||
                missing.single != slug ||
                pages.isNotEmpty)) ||
        (works.isNotEmpty && missing.isNotEmpty)) {
      throw const FormatException('Invalid export selection');
    }
    if (works.isEmpty) {
      return const NotionExportResult(
        missing: true,
        bundleJson: '',
        issues: [],
        editions: [],
      );
    }
    final work = works.single;
    if (work is! Map<String, dynamic> ||
        work['slug'] != slug ||
        work['pages'] is! List) {
      throw const FormatException('Invalid export work');
    }
    final workPages = work['pages'] as List;
    if (workPages.isEmpty || workPages.length != pages.length) {
      throw const FormatException('Invalid export editions');
    }
    final bundleIds = <String>{};
    for (final page in pages) {
      if (page is! Map<String, dynamic> ||
          page['id'] is! String ||
          (page['id'] as String).isEmpty ||
          !bundleIds.add(page['id'] as String) ||
          page['properties'] is! Map<String, dynamic> ||
          page['blocks'] is! List) {
        throw const FormatException('Invalid export bundle');
      }
    }
    final remainingIds = Set<String>.of(bundleIds);
    final editions = <NotionExportEdition>[];
    for (final page in workPages) {
      if (page is! Map<String, dynamic> ||
          page['locale'] is! String ||
          page['pageId'] is! String ||
          !remainingIds.remove(page['pageId']) ||
          (page['provenance'] != 'notion' && page['provenance'] != 'site')) {
        throw const FormatException('Invalid export edition');
      }
      editions.add(
        NotionExportEdition(
          locale: page['locale'] as String,
          fromNotion: page['provenance'] == 'notion',
          issues: _issueCodes(page['issues']),
        ),
      );
    }
    return NotionExportResult(
      missing: false,
      bundleJson: jsonEncode(bundle),
      issues: _issueCodes(work['issues']),
      editions: List.unmodifiable(editions),
    );
  }

  List<String> _issueCodes(dynamic value) {
    if (value is! List) throw const FormatException('Invalid export issues');
    final codes = <String>[];
    for (final issue in value) {
      if (issue is! Map<String, dynamic> ||
          issue['code'] is! String ||
          issue['detail'] is! String) {
        throw const FormatException('Invalid export issue');
      }
      codes.add(issue['code'] as String);
    }
    return List.unmodifiable(codes);
  }
}
