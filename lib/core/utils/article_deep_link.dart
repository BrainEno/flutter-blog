/// Deep-link contract for articles (issue #21).
///
/// Two shapes are understood:
///
/// 1. `nowave://article/<slug>` - the custom scheme both platforms register.
///    It works today: no web origin, no hosted association files, no domain
///    verification. This is what the app can honestly claim.
/// 2. `https://<WEB_BASE_URL>/articles/<slug>` - the canonical web URL that
///    `articleWebUrl` hands to the share sheet. It is parsed here so a link
///    that *does* reach the app (app link / universal link once the
///    association files are deployed) lands on the same reader. Until then
///    the URL opens the web article, which is the documented fallback; the
///    host must match `WEB_BASE_URL`, so the app never hijacks a foreign
///    site's `/articles/...` path.
///
/// This file is pure Dart - no widgets, no router - so the mapping is unit
/// tested without pumping an app.
library;

import 'package:belog/core/secrets/app_secrets.dart';

/// Scheme registered in `android/app/src/main/AndroidManifest.xml` and
/// `ios/Runner/Info.plist`.
const String kArticleDeepLinkScheme = 'nowave';

/// Host of the custom-scheme form. `nowave://article/<slug>` keeps the slug
/// in the first path segment, which is the shape a share sheet and a QR code
/// can carry without escaping slashes.
const String kArticleDeepLinkHost = 'article';

/// Path segment the no-wave web app serves article pages under.
const String kArticleWebPathSegment = 'articles';

/// The shareable custom-scheme link for [slug].
///
/// Prefer [articleWebUrl] for anything a human will read or click: a
/// `nowave://` link only opens on a device with the app installed. This form
/// exists for in-app/QR/native handoff, where no browser is involved.
String articleDeepLink(String slug) {
  final trimmed = slug.trim();
  if (trimmed.isEmpty) return '';
  return '$kArticleDeepLinkScheme://$kArticleDeepLinkHost'
      '/${Uri.encodeComponent(trimmed)}';
}

/// The in-app route for an incoming [uri], or null when the URI is not an
/// article deep link.
///
/// Null is the important answer: the router treats every other URL exactly as
/// before, so a link to an unknown scheme, a foreign host or a missing slug
/// keeps normal GoRouter behaviour (404 page with a way home) instead of
/// being rewritten into a fake article.
///
/// [webBaseUrl] overrides the configured `WEB_BASE_URL`, mirroring
/// `articleWebUrl`.
String? articleLocationFromDeepLink(Uri uri, {String? webBaseUrl}) {
  final slug =
      _slugFromCustomScheme(uri) ?? _slugFromWebUrl(uri, webBaseUrl: webBaseUrl);
  if (slug == null) return null;
  return '/view/${Uri.encodeComponent(slug)}';
}

/// Resolves the platform's initial route (`PlatformDispatcher.defaultRouteName`)
/// into the location the router should start at.
///
/// A cold start from a link hands the whole URL over as the initial route. It
/// is translated here, before the router exists, so the first frame is already
/// the article; anything that is neither an article deep link nor an in-app
/// path starts at the feed instead of showing a 404 the reader cannot explain.
String initialLocationForRoute(String? routeName) {
  final raw = routeName?.trim();
  if (raw == null || raw.isEmpty || raw == '/') return '/';
  final uri = Uri.tryParse(raw);
  if (uri == null) return '/';
  final deepLink = articleLocationFromDeepLink(uri);
  if (deepLink != null) return deepLink;
  return raw.startsWith('/') ? raw : '/';
}

/// `nowave://article/<slug>` and `nowave:///article/<slug>`.
String? _slugFromCustomScheme(Uri uri) {
  if (uri.scheme.toLowerCase() != kArticleDeepLinkScheme) return null;
  var segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (uri.host == kArticleDeepLinkHost) {
    // nowave://article/<slug>
  } else if (uri.host.isEmpty &&
      segments.isNotEmpty &&
      segments.first == kArticleDeepLinkHost) {
    // nowave:///article/<slug>
    segments = segments.sublist(1);
  } else {
    return null;
  }
  if (segments.length != 1) return null;
  return _usableSlug(segments.single);
}

/// `https://<WEB_BASE_URL>[/base]/articles/<slug>`.
String? _slugFromWebUrl(Uri uri, {String? webBaseUrl}) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final configured = (webBaseUrl ?? AppSecrets.webBaseUrl)?.trim();
  if (configured == null || configured.isEmpty) return null;
  final base = Uri.tryParse(configured);
  if (base == null || base.host.isEmpty) return null;
  if (base.host.toLowerCase() != uri.host.toLowerCase()) return null;

  final basePath = base.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length != basePath.length + 2) return null;
  for (var i = 0; i < basePath.length; i++) {
    if (segments[i] != basePath[i]) return null;
  }
  if (segments[basePath.length] != kArticleWebPathSegment) return null;
  return _usableSlug(segments.last);
}

/// Slugs address a public article. Anything empty, overlong or containing
/// whitespace cannot be one (the backend slugs are `ascii-stem-hash`), so it is
/// refused rather than turned into a request.
String? _usableSlug(String value) {
  final slug = value.trim();
  if (slug.isEmpty || slug.length > 200) return null;
  if (RegExp(r'\s').hasMatch(slug)) return null;
  if (slug == '.' || slug == '..') return null;
  return slug;
}
