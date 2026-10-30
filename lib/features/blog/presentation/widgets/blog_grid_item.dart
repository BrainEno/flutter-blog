import 'package:belog/core/utils/extract_description.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';

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

    return GestureDetector(
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
                        color: Colors.black.withAlpha((0.35 * 255).toInt()),
                        colorBlendMode: BlendMode.darken,
                      )
                    : Container(color: Colors.grey[300]),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          blog.posterName ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 12.0,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          blog.updatedAt.toString().substring(0, 10),
                          style: const TextStyle(
                            fontSize: 10.0,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),

                    // Date
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
