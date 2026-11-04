import 'dart:io';

import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/utils/cover_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

/// The tappable cover slot: the newly picked file, the published cover, or a
/// dashed placeholder that opens the picker.
class EditorCoverField extends StatelessWidget {
  const EditorCoverField({
    super.key,
    this.blog,
    this.image,
    this.isNewImageSelected = false,
    required this.onTap,
  });

  /// The article being edited, if any; its cover is shown until replaced.
  final Blog? blog;

  /// The newly picked file, if any.
  final File? image;

  /// Whether [image] replaces the published cover.
  final bool isNewImageSelected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.uploadCoverHint,
      child: Semantics(
        image: true,
        label: context.l10n.coverImage,
        child: InkWell(onTap: onTap, child: _cover(context)),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final picked = image;
    if (picked != null && isNewImageSelected) {
      return SizedBox(
        height: 250,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(picked, fit: BoxFit.cover),
        ),
      );
    }
    final published = blog;
    if (published != null && published.imageUrl.isNotEmpty) {
      return SizedBox(
        height: 250,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            // Cover URLs are immutable and shared with the reader.
            imageUrl: coverUrlOf(published),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final muted = isDarkMode ? AppPalette.mutedOnInk : AppPalette.mutedOnPaper;
    final dashedColor = isDarkMode
        ? AppPalette.mutedOnInk.withAlpha((0.6 * 255).toInt())
        : AppPalette.mutedOnPaper.withAlpha((0.8 * 255).toInt());
    final surface = isDarkMode
        ? AppPalette.surfaceOnInk.withAlpha((0.3 * 255).toInt())
        : AppPalette.surfaceOnPaper.withAlpha((0.15 * 255).toInt());
    return DottedBorder(
      color: dashedColor,
      radius: const Radius.circular(12),
      borderType: BorderType.RRect,
      dashPattern: const [6, 3],
      strokeCap: StrokeCap.round,
      child: Container(
        constraints: const BoxConstraints(minHeight: 250),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: surface,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 55, color: muted),
              const SizedBox(height: 12),
              Text(
                context.l10n.uploadCoverHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
