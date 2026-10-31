import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Renders the actual immutable cover when available, with a bundled offline
/// editorial fallback for absent, invalid, loading or failed image URLs.
class ArticleCover extends StatelessWidget {
  const ArticleCover({
    super.key,
    required this.title,
    required this.imageUrl,
    this.aspectRatio = 16 / 10,
  });

  final String title;
  final String imageUrl;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final uri = Uri.tryParse(url);
    final validUrl =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    Widget fallback() => Image.asset(
      'assets/images/no_wave_cover_fallback.jpg',
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );

    return Semantics(
      image: true,
      label: context.l10n.coverOf(title),
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ColoredBox(
            color: AppPalette.ink,
            child: validUrl
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
    );
  }
}
