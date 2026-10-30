import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/extract_description.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';

/// Give grid cards additional vertical space when the system font grows.
SliverGridDelegateWithFixedCrossAxisCount blogGridDelegate(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
    mainAxisExtent: 270 * (scale < 1 ? 1 : scale),
  );
}

class BlogGridItem extends StatelessWidget {
  final Blog blog;
  final VoidCallback onTap;

  /// Long-press action (delete in "my articles"); absent by default.
  final VoidCallback? onLongPress;

  const BlogGridItem({
    super.key,
    required this.blog,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final description = extractDescription(blog.content);

    // One tappable control per card for switches; the title doubles as
    // the semantic label (issue #24).
    return Semantics(
      button: true,
      label: context.l10n.coverOf(blog.title),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Card(
          elevation: 4.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: Stack(
              children: [
                // Background image with gradient overlay
                Positioned.fill(
                  child: blog.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl:
                              '${blog.imageUrl}?v=${blog.updatedAt.microsecondsSinceEpoch}',
                          fit: BoxFit.cover,
                          color: Colors.black.withAlpha((0.70 * 255).toInt()),
                          colorBlendMode: BlendMode.darken,
                        )
                      : Container(color: Colors.grey[900]),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Title
                      Text(
                        blog.title,
                        style: const TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Description
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 14.0,
                          color: Colors.white70,
                        ),
                        maxLines: 7,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // Poster info
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            blog.posterName?.trim().isNotEmpty == true
                                ? blog.posterName!
                                : context.l10n.anonymousAuthor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            formatDate(context.l10n, blog.updatedAt),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      // Date
                    ],
                  ),
                ),
                if (onLongPress != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filledTonal(
                      tooltip: context.l10n.deleteArticleTitle,
                      onPressed: onLongPress,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
