import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/utils/article_deep_link.dart';
import 'package:share_plus/share_plus.dart';

/// Canonical public URL of an article (issue #21).
///
/// The no-wave web app serves article pages at `/articles/{slug}`
/// (`apps/web/src/app/articles/[slug]`), on its own origin. The origin
/// comes from the `WEB_BASE_URL` dart-define - never guessed from the API
/// origin - and the URL is assembled in exactly one place so no page can
/// invent its own format.
String? articleWebUrl(String slug, {String? webBaseUrl}) {
  final base = (webBaseUrl ?? AppSecrets.webBaseUrl)?.trim();
  if (base == null || base.isEmpty || slug.isEmpty) {
    return null;
  }
  return '${base.replaceAll(RegExp(r'/+$'), '')}'
      '/$kArticleWebPathSegment/$slug';
}

/// The share-sheet body: the title, an optional plain-text blurb, then the
/// canonical URL on its own line so every target can linkify it.
String shareArticleText({
  required String title,
  required String url,
  String? summary,
}) {
  final blurb = (summary ?? '').trim();
  return [
    title.trim(),
    if (blurb.isNotEmpty) blurb,
    url,
  ].join('\n\n');
}

/// A single plain-text paragraph from a Markdown body, for the share sheet.
///
/// Deliberately shallow: it unwraps headings, quotes, list bullets, links and
/// emphasis, then takes the first line that still has text. It is a blurb, not
/// a renderer - the reader itself decides how the body looks.
String shareSummary(String content, {int maxChars = 140}) {
  var insideFence = false;
  for (final rawLine in content.split(RegExp(r'\r?\n'))) {
    var line = rawLine.trim();
    // Fenced code is never a blurb, and its content is not prose either.
    if (line.startsWith('```') || line.startsWith('~~~')) {
      insideFence = !insideFence;
      continue;
    }
    if (insideFence || line.isEmpty) continue;
    if (RegExp(r'^([-*_=]{3,})$').hasMatch(line)) continue;
    line = line
        .replaceAll(RegExp(r'^#{1,6}\s*'), '')
        .replaceAll(RegExp(r'^>\s*'), '')
        .replaceAll(RegExp(r'^[-*+]\s+'), '');
    line = line
        .replaceAllMapped(
          RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[*_~`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.isEmpty) continue;
    final runes = line.runes.toList();
    if (runes.length <= maxChars) return line;
    return '${String.fromCharCodes(runes.take(maxChars)).trimRight()}…';
  }
  return '';
}

/// Opens the system share sheet with the article's title, a short excerpt and
/// its canonical URL. Only public, resolvable links are ever shared - no local
/// file paths, tokens or short-lived URLs.
Future<void> shareArticle({
  required String title,
  required String slug,
  String? summary,
}) async {
  final url = articleWebUrl(slug);
  if (url == null) return;
  await SharePlus.instance.share(
    ShareParams(
      title: title,
      text: shareArticleText(title: title, url: url, summary: summary),
    ),
  );
}
