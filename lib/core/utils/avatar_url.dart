import 'package:belog/core/utils/article_resource_url.dart';

/// Resolves a no-wave profile `avatarUrl` into a URL an image widget may load.
///
/// The backend accepts more than absolute HTTP(S) URLs: no-wave's
/// `validateProfileUrl(..., allowRelative: true)` also allows single-slash
/// site-relative avatars such as `/avatars/me.webp`. A relative avatar belongs
/// to the public web deployment, whose origin is *not* derivable from the API
/// origin (they are separate deployments), so it is resolved only against an
/// explicitly configured `WEB_BASE_URL`.
///
/// Returns `null` when the value cannot be rendered safely: no configured web
/// origin, protocol-relative (`//host/...`), a non-HTTP scheme (`javascript:`,
/// `data:`, `file:`), embedded credentials, surrounding whitespace or control
/// characters, or a resolution that would leave the configured origin. The
/// caller then keeps its neutral portrait. This never rewrites the stored
/// value, the profile model or the exported data.
String? resolveAvatarUrl(String? value, {String? webBaseUrl}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  return resolveArticleResourceUrl(raw, webBaseUrl: webBaseUrl)?.toString();
}
