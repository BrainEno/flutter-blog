import 'package:belog/core/secrets/app_secrets.dart';
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
  return '${base.replaceAll(RegExp(r'/+$'), '')}/articles/$slug';
}

/// Opens the system share sheet with the article's title and canonical
/// URL. Only public, resolvable links are ever shared - no local file
/// paths, tokens or short-lived URLs.
Future<void> shareArticle({required String title, required String slug}) async {
  final url = articleWebUrl(slug);
  if (url == null) return;
  await SharePlus.instance.share(
    ShareParams(title: title, text: '$title\n$url'),
  );
}
