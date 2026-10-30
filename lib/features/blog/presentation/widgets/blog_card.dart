import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/tag_l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/utils/cover_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BlogCard extends StatefulWidget {
  const BlogCard({super.key, required this.blog});
  final Blog blog;

  @override
  State<BlogCard> createState() => _BlogCardState();
}

class _BlogCardState extends State<BlogCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 150),
    vsync: this,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 0.95,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _tagColor(String tag) => switch (tag) {
    '诗歌' => const Color(0xFFB42318),
    '小说' => const Color(0xFF005B85),
    '原创' => const Color(0xFF6931A8),
    _ => const Color(0xFF805000),
  };

  @override
  Widget build(BuildContext context) {
    final blog = widget.blog;
    final l10n = context.l10n;
    final name = blog.posterName?.trim().isNotEmpty == true
        ? blog.posterName!
        : l10n.anonymousAuthor;
    return Semantics(
      image: true,
      label: l10n.coverOf(blog.title),
      child: InkWell(
        onTap: () => context.push('/view/${blog.id}', extra: blog),
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) => _controller.reverse(),
        onTapCancel: () => _controller.reverse(),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            constraints: const BoxConstraints(minHeight: 210),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 6),
                ),
              ],
              image: blog.imageUrl.isEmpty
                  ? null
                  : DecorationImage(
                      image: CachedNetworkImageProvider(coverUrlOf(blog)),
                      fit: BoxFit.cover,
                    ),
            ),
            // The gradient is painted *over* the cover and behind the text.
            // A sufficiently dark overlay keeps white text legible even on
            // a white cover; the card grows with the system text scale.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.black87],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (blog.tags.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final tag in blog.tags)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text(
                                    localizedTag(l10n, tag),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: _tagColor(tag),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      blog.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(name, style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatDate(
                          Localizations.localeOf(context),
                          blog.updatedAt,
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
