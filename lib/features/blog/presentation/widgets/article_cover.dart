import 'package:belog/core/design/cover/no_wave_cover_plate.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/article_resource_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Renders the actual immutable cover when available, with a bundled offline
/// editorial plate for absent, invalid, loading or failed image URLs.
///
/// The plate is chosen once, from [seed], before the network is asked: the
/// placeholder, the error state and the final frame therefore show the same
/// image. A cover that changes when the request fails reads as a different
/// article, not as a missing picture.
class ArticleCover extends StatelessWidget {
  const ArticleCover({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.seed,
    this.aspectRatio = 16 / 10,
  });

  final String title;
  final String imageUrl;

  /// The article's stable identity (its slug or id) - what [NoWaveCoverPlate]
  /// hashes. Not the title: a retitled article keeps its plate.
  final String seed;

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final uri = resolveArticleResourceUrl(imageUrl);
    final plate = NoWaveCoverPlate.forSeed(seed);
    Widget fallback() => Image.asset(
      plate.asset,
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
            child: uri != null
                ? CachedNetworkImage(
                    imageUrl: uri.toString(),
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
