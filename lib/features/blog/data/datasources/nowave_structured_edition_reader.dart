import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/entities/structured_session_metadata.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:http/http.dart' as http;

/// Uses the only current REST read that includes an author's drafts: a limited
/// `/me/articles` list. It cannot prove absence when the target is not listed.
/// No public-detail fallback or mutation is attempted.
class NowaveStructuredEditionReader implements StructuredEditionReader {
  const NowaveStructuredEditionReader(this.client);
  final NowaveApiClient client;

  @override
  Future<StructuredEditionReadResult> read({
    required StructuredBodyKey key,
    required NowaveSessionFence fence,
  }) async {
    if (key.userId != fence.userId ||
        fence.userId.isEmpty ||
        fence.userId != fence.userId.trim()) {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.sessionChanged,
      );
    }
    try {
      final data = await client.getJson(
        '/me/articles',
        query: {'limit': '100', 'locale': key.locale},
        sessionFence: fence,
        followRedirects: false,
      );
      return decodeStructuredEditionWindow(data, key: key);
    } on NowaveApiException catch (error) {
      if (error.code == 'SESSION_CHANGED') {
        return const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.sessionChanged,
        );
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const StructuredEditionReadResult.failed(
          StructuredEditionReadStatus.authenticationRequired,
        );
      }
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
    } on SocketException {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
    } on TimeoutException {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
    } on http.ClientException {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unavailable,
      );
    } on FormatException {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.invalidResponse,
      );
    }
  }
}

const _knownFields = {
  'id',
  'authorId',
  'slug',
  'workType',
  'status',
  'locale',
  'title',
  'summary',
  'contentBlocks',
  'contentBlocksVersion',
  'createdAt',
  'updatedAt',
  'publishedAt',
  'viewCount',
  'author',
  'categories',
  'tags',
};

/// Decoder factored out to exercise malformed and older deployment responses.
/// Other rows must have valid IDs: otherwise they might conceal a duplicate.
StructuredEditionReadResult decodeStructuredEditionWindow(
  Object? value, {
  required StructuredBodyKey key,
}) {
  if (value is! List || value.length > 100) {
    return const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.invalidResponse,
    );
  }
  Map<String, dynamic>? selected;
  var mismatch = false;
  for (final row in value) {
    if (row is! Map ||
        row.keys.any((key) => key is! String) ||
        row['id'] is! String ||
        (row['id'] as String).isEmpty) {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.invalidResponse,
      );
    }
    if (row['id'] != key.articleId) continue;
    if (row['authorId'] != key.userId || row['locale'] is! String) {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.invalidResponse,
      );
    }
    if (row['locale'] != key.locale) {
      mismatch = true;
      continue;
    }
    if (selected != null)
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.invalidResponse,
      );
    selected = row.cast<String, dynamic>();
  }
  if (mismatch)
    return const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.editionMismatch,
    );
  if (selected == null)
    return const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.notInAuthorWindow,
    );
  try {
    final raw = jsonEncode(selected);
    // Bound one article projection, including its author and taxonomy fields.
    if (raw.length > 2000000)
      throw const FormatException('Article projection too large');
    final detached = jsonDecode(raw) as Map<String, dynamic>;
    final StructuredArticleDraft document;
    try {
      document = StructuredArticleDraft.parse(
        version: detached['contentBlocksVersion'],
        blocks: detached['contentBlocks'],
      );
    } on FormatException {
      return const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.unsupportedDocument,
      );
    }
    final issues = <StructuredMetadataIssue>{};
    String? text(String field, StructuredMetadataIssue missing) {
      final item = detached[field];
      if (item == null) {
        issues.add(missing);
        return null;
      }
      if (item is! String)
        throw const FormatException('Invalid metadata field');
      return item;
    }

    final status = text(
      'status',
      StructuredMetadataIssue.missingPublicationState,
    );
    final String? publicationState;
    if (status == null || status == 'draft' || status == 'published') {
      publicationState = status;
    } else {
      publicationState = null;
      issues.add(StructuredMetadataIssue.unknownPublicationState);
    }
    StructuredTaxonomySelection? selection(
      String field,
      String property,
      StructuredMetadataIssue missing,
    ) {
      final raw = detached[field];
      if (raw == null) {
        issues.add(missing);
        return null;
      }
      if (raw is! List || raw.length > 100)
        throw const FormatException('Invalid taxonomy');
      final values = <String>[];
      for (final item in raw) {
        if (item is! Map || item[property] is! String)
          throw const FormatException('Invalid taxonomy row');
        values.add(item[property] as String);
      }
      return StructuredTaxonomySelection(values: values, touched: false);
    }

    if (detached.keys.any((field) => !_knownFields.contains(field)))
      issues.add(StructuredMetadataIssue.unknownArticleFields);
    final metadata = StructuredSessionMetadata(
      slug: text('slug', StructuredMetadataIssue.missingSlug),
      title: text('title', StructuredMetadataIssue.missingTitle),
      summary: text('summary', StructuredMetadataIssue.missingSummary),
      workType: text('workType', StructuredMetadataIssue.missingWorkType),
      publicationState: publicationState,
      tags: selection('tags', 'name', StructuredMetadataIssue.missingTags),
      categories: selection(
        'categories',
        'id',
        StructuredMetadataIssue.missingCategories,
      ),
      // Server image blocks are not an explicit cover-selection state.
      cover: null,
    );
    return StructuredEditionReadResult.found(
      StructuredEdition(
        key: key,
        body: document,
        metadata: metadata,
        rawArticle: detached,
        metadataIssues: issues,
      ),
    );
  } on FormatException {
    return const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.invalidResponse,
    );
  } on JsonUnsupportedObjectError {
    return const StructuredEditionReadResult.failed(
      StructuredEditionReadStatus.invalidResponse,
    );
  }
}
