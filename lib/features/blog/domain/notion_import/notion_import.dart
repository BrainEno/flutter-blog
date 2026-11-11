import 'dart:convert';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:fpdart/fpdart.dart';

/// A validated, immutable-by-convention bundle snapshot. It is never persisted.
class NotionBundle {
  NotionBundle._(this.json);
  final Map<String, dynamic> json;

  static const maxRequestBytes = 8 * 1024 * 1024;
  static const maxPages = 200;

  static NotionBundle parse(String input) {
    // Avoid decoding a huge paste; also account for the request envelope below.
    if (utf8.encode(input).length > maxRequestBytes) {
      throw const FormatException('size');
    }
    final dynamic decoded = jsonDecode(
      input.replaceFirst(RegExp(r'^\uFEFF'), ''),
    );
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['pages'] is! List) {
      throw const FormatException('bundle');
    }
    final pages = decoded['pages'] as List;
    if (pages.length > maxPages) throw const FormatException('pages');
    for (final page in pages) {
      if (page is! Map<String, dynamic> ||
          page['id'] is! String ||
          (page['id'] as String).isEmpty ||
          page['properties'] is! Map<String, dynamic> ||
          page['blocks'] is! List) {
        throw const FormatException('page');
      }
    }
    final encoded = jsonEncode({'bundle': decoded, 'apply': true});
    if (utf8.encode(encoded).length > maxRequestBytes) {
      throw const FormatException('size');
    }
    return NotionBundle._(decoded);
  }

  /// Positions are used rather than server report IDs: the server may omit an
  /// invalid translation or scope a filename ID to the signed-in account.
  int get pageCount => (json['pages'] as List).length;

  String pageTitle(int index) {
    final page = (json['pages'] as List)[index] as Map<String, dynamic>;
    final properties = page['properties'] as Map<String, dynamic>;
    for (final property in properties.values) {
      if (property is Map<String, dynamic> && property['type'] == 'title') {
        final parts = property['title'];
        if (parts is! List) return '';
        return parts
            .whereType<Map<String, dynamic>>()
            .map(
              (part) => part['plain_text'] is String
                  ? part['plain_text'] as String
                  : '',
            )
            .join()
            .trim();
      }
    }
    return '';
  }

  /// Retain the source page order, metadata, and relationships unchanged.
  /// Selection is local only; the server still decides whether it is valid.
  NotionBundle selectPages(Set<int> indices) {
    if (indices.isEmpty ||
        indices.any((index) => index < 0 || index >= pageCount)) {
      throw const FormatException('selection');
    }
    final pages = json['pages'] as List;
    return NotionBundle._({
      ...json,
      'pages': [
        for (var i = 0; i < pages.length; i++)
          if (indices.contains(i)) pages[i],
      ],
    });
  }
}

enum NotionImportAction { create, update, skip, refused, failed }

class NotionImportIssue {
  const NotionImportIssue({required this.code, required this.detail});
  final String code;
  final String detail;
}

class NotionImportPage {
  const NotionImportPage({
    required this.title,
    required this.locale,
    required this.action,
    required this.detail,
    required this.issues,
    this.externalId = '',
    this.slug = '',
    this.articleId,
  });
  final String title;
  final String externalId;
  final String slug;
  final String? articleId;
  final String locale;
  final NotionImportAction action;
  final String detail;
  final List<NotionImportIssue> issues;
}

class NotionImportReport {
  const NotionImportReport({
    required this.applied,
    required this.pages,
    this.omittedPages = 0,
  });
  final bool applied;

  /// The server can omit invalid linked editions from the page report.
  final int omittedPages;
  final List<NotionImportPage> pages;
  int count(NotionImportAction action) =>
      pages.where((p) => p.action == action).length;
  bool get canApply =>
      !applied &&
      pages.any(
        (p) =>
            p.action == NotionImportAction.create ||
            p.action == NotionImportAction.update,
      );
}

abstract interface class NotionImportRepository {
  Future<Either<Failure, NotionImportReport>> submit({
    required NotionBundle bundle,
    required bool apply,
    required NowaveSessionFence sessionFence,
  });
}
