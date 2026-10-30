import 'dart:convert';
import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Builds the export document (issue #22): the user's profile and every
/// article they posted, as plain JSON.
///
/// Pure function so the shape stays unit-tested. Field names describe the
/// data (not the old Supabase schema); `slug` is the article's public id.
/// Dates are UTC ISO-8601 so the file is portable across time zones.
Map<String, Object?> buildUserDataExport({
  required User user,
  required List<Blog> articles,
  DateTime? now,
}) {
  return {
    'format': 'belog-user-data-export',
    'version': 1,
    'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'profile': {
      'id': user.id,
      'email': user.email,
      'name': user.name,
      'avatarUrl': user.avatarUrl,
      'website': user.website,
      'updatedAt': user.updatedAt.toUtc().toIso8601String(),
    },
    'articles': [
      for (final article in articles)
        {
          'slug': article.id,
          'title': article.title,
          'content': article.content,
          'tags': article.tags,
          'posterId': article.posterId,
          'imageUrl': article.imageUrl,
          'updatedAt': article.updatedAt.toUtc().toIso8601String(),
        },
    ],
  };
}

/// Exports the signed-in user's data to a JSON file and hands it to the
/// system share sheet (issue #22).
///
/// The file is written into the app's temporary directory - a scratch area
/// the OS may reclaim - because the canonical copy is whatever destination
/// the user picks in the share sheet.
class UserDataExporter {
  final GetBlogsByPoster getBlogsByPoster;

  /// Injectable for tests.
  final Future<Directory> Function() temporaryDirectory;

  const UserDataExporter({
    required this.getBlogsByPoster,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  /// Fetches the user's articles and shares the export file.
  /// [Failure] messages are user-facing (see [error_mapper]).
  Future<Either<Failure, void>> exportAndShare({
    required User user,
    String shareTitle = '我的 Belog 数据',
  }) async {
    final articlesRes = await getBlogsByPoster(
      GetBlogsByPosterParams(userId: user.id),
    );
    final failure = articlesRes.getLeft().toNullable();
    if (failure != null) {
      return left(failure);
    }
    final articles = articlesRes.getRight().toNullable() ?? const <Blog>[];

    final document = buildUserDataExport(user: user, articles: articles);
    final now = DateTime.now();
    final stamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final directory = await temporaryDirectory();
    final file = File('${directory.path}/belog-export-$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
    );
    await SharePlus.instance.share(
      ShareParams(title: shareTitle, files: [XFile(file.path)]),
    );
    return right(null);
  }
}
