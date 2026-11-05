import 'package:belog/l10n/app_localizations.dart';

/// Display names arrive from the backend as free text and are sometimes empty
/// or blank: a deleted account, a comment written before a display name
/// existed, an author whose name never came back with the article.
///
/// Every caller repeated the same `trim().isEmpty ? fallback : raw` check, and
/// one of them compared without trimming, so a whitespace-only name rendered as
/// an empty label. Both fallbacks live here now; the value itself is returned
/// unchanged (no trimming) so the rendered text stays exactly what the backend
/// sent whenever it is usable.
///
/// Accessible name for an article or profile author.
String authorDisplayName(AppLocalizations l10n, String? raw) {
  return _orFallback(raw, l10n.anonymousAuthor);
}

/// Same for comment authors: a comment is written by a reader, so the fallback
/// is "anonymous reader" rather than "anonymous author".
String commentAuthorDisplayName(AppLocalizations l10n, String? raw) {
  return _orFallback(raw, l10n.anonymousReader);
}

String _orFallback(String? raw, String fallback) {
  final name = raw ?? '';
  return name.trim().isEmpty ? fallback : name;
}
