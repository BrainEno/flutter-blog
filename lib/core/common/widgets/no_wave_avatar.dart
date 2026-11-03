import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/avatar_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A square portrait for the reader and profile surfaces.
///
/// The name is supplied by the caller (including its localized anonymous
/// fallback). A missing, invalid, loading or failed image remains a neutral
/// portrait, not invented author content.
///
/// [imageUrl] may be an absolute HTTP(S) URL or - like the backend allows - a
/// site-relative path such as `/avatars/me.webp`. Relative avatars resolve
/// against the configured `WEB_BASE_URL` only (never the API origin); without
/// one they stay neutral. [webBaseUrl] overrides that configuration, which is
/// what the tests use.
class NoWaveAvatar extends StatelessWidget {
  const NoWaveAvatar({
    super.key,
    required this.name,
    this.imageUrl = '',
    this.size = 80,
    this.webBaseUrl,
  });

  final String name;
  final String imageUrl;
  final double size;
  final String? webBaseUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Null means "not safely renderable": keep the neutral portrait rather
    // than loading an unverified host.
    final url = resolveAvatarUrl(imageUrl, webBaseUrl: webBaseUrl);

    Widget fallback() => Center(
      child: Icon(
        Icons.person_outline,
        size: size * 0.45,
        color: scheme.onSurfaceVariant,
      ),
    );

    return Semantics(
      container: true,
      image: true,
      label: context.l10n.avatarOf(name),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: ClipRect(
              child: url != null
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => fallback(),
                      errorWidget: (_, _, _) => fallback(),
                    )
                  : fallback(),
            ),
          ),
        ),
      ),
    );
  }
}
