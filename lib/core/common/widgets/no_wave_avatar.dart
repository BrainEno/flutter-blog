import 'package:belog/core/l10n/l10n.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A square portrait for the reader and profile surfaces.
///
/// The name is supplied by the caller (including its localized anonymous
/// fallback). A missing, invalid, loading or failed image remains a neutral
/// portrait, not invented author content.
class NoWaveAvatar extends StatelessWidget {
  const NoWaveAvatar({
    super.key,
    required this.name,
    this.imageUrl = '',
    this.size = 80,
  });

  final String name;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl.trim();
    final uri = Uri.tryParse(url);
    final isNetworkImage =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    Widget fallback() => Center(
      child: Icon(
        Icons.person_outline,
        size: size * 0.45,
        color: scheme.onSurfaceVariant,
      ),
    );

    return Semantics(
      image: true,
      label: context.l10n.avatarOf(name),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: ClipRect(
              child: isNetworkImage
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
