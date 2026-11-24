import 'dart:typed_data';

import 'package:belog/core/common/media/no_wave_image_decode_size.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

/// The tappable cover slot: the new cover, the published one, or a dashed
/// placeholder that opens the picker.
///
/// The slot has the reader's cover shape ([NoWaveSizes.coverAspectWide]), so
/// what the author sees here is what the article header shows - not a strip of
/// it, as a fixed-height box would draw on a wide screen.
class EditorCoverField extends StatelessWidget {
  const EditorCoverField({
    super.key,
    this.blog,
    this.imageBytes,
    this.selectedCoverUrl,
    this.isNewImageSelected = false,
    required this.onTap,
  });

  /// The article being edited, if any; its cover is shown until replaced.
  final Blog? blog;

  /// The new cover's bytes: the cut photo, or a resumed queue entry's stored
  /// cover.
  final Uint8List? imageBytes;

  /// An immutable cover asset selected from the user's media library.
  final String? selectedCoverUrl;

  /// Whether a newly selected cover replaces the published cover.
  final bool isNewImageSelected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.uploadCoverHint,
      child: Semantics(
        image: true,
        label: context.l10n.coverImage,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Before the parent has a width, the screen's is a safe upper
              // bound for the decode budget.
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.of(context).size.width;
              return _cover(context, width);
            },
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, double width) {
    final decode = noWaveDecodeSizeForFixed(
      context,
      logicalWidth: width,
      logicalHeight: width / NoWaveSizes.coverAspectWide,
    );
    final bytes = imageBytes;
    if (bytes != null && isNewImageSelected) {
      return _frame(
        Image.memory(
          bytes,
          key: const Key('editor-cover-bytes'),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: decode.width,
          cacheHeight: decode.height,
        ),
      );
    }
    final selectedCover = selectedCoverUrl;
    if (isNewImageSelected &&
        selectedCover != null &&
        selectedCover.isNotEmpty) {
      return _frame(
        CachedNetworkImage(
          imageUrl: selectedCover,
          fit: BoxFit.cover,
          memCacheWidth: decode.width,
          memCacheHeight: decode.height,
        ),
      );
    }
    // The editor's cover: for a structured article only a leading image is
    // one, and its other pictures stay in the body text.
    final publishedCover = blog?.editableBody?.coverUrl ?? blog?.imageUrl ?? '';
    if (publishedCover.isNotEmpty) {
      return _frame(
        CachedNetworkImage(
          // Cover media are immutable on no-wave (each upload is a new
          // asset id), so the URL is used as-is: no cache-busting suffix.
          imageUrl: publishedCover,
          fit: BoxFit.cover,
          memCacheWidth: decode.width,
          memCacheHeight: decode.height,
        ),
      );
    }
    return _placeholder(context, width);
  }

  Widget _frame(Widget image) => AspectRatio(
    aspectRatio: NoWaveSizes.coverAspectWide,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(NoWaveRadius.container),
      child: image,
    ),
  );

  Widget _placeholder(BuildContext context, double width) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final muted = isDarkMode ? AppPalette.mutedOnInk : AppPalette.mutedOnPaper;
    final dashedColor = isDarkMode
        ? AppPalette.mutedOnInk.withAlpha((0.6 * 255).toInt())
        : AppPalette.mutedOnPaper.withAlpha((0.8 * 255).toInt());
    final surface = isDarkMode
        ? AppPalette.surfaceOnInk.withAlpha((0.3 * 255).toInt())
        : AppPalette.surfaceOnPaper.withAlpha((0.15 * 255).toInt());
    return DottedBorder(
      // dotted_border 3 moves paint configuration into one typed options
      // object. Keep the former rounded, softly dashed visual treatment.
      options: RoundedRectDottedBorderOptions(
        color: dashedColor,
        radius: const Radius.circular(NoWaveRadius.container),
        dashPattern: const [6, 3],
        strokeCap: StrokeCap.round,
      ),
      child: Container(
        // The cover's shape at least, taller when a large text size needs it.
        constraints: BoxConstraints(
          minHeight: width / NoWaveSizes.coverAspectWide,
        ),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NoWaveRadius.container),
          color: surface,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 55, color: muted),
              const SizedBox(height: NoWaveSpacing.small),
              Text(
                context.l10n.uploadCoverHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: NoWaveTypeScale.hint,
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

/// What the author can do with the cover, under the slot. The slot itself
/// still opens the picker on a tap; these say so, and add the moves a tap
/// cannot: the media library, reframing a picked photo, and backing out.
class EditorCoverActions extends StatelessWidget {
  const EditorCoverActions({
    super.key,
    required this.hasCover,
    required this.hasPublishedCover,
    required this.onPick,
    required this.onChooseFromLibrary,
    this.onRecrop,
    this.onClear,
  });

  /// Whether the slot shows any cover, new or published.
  final bool hasCover;

  /// Whether the article already has a cover to fall back to.
  final bool hasPublishedCover;

  final VoidCallback onPick;
  final VoidCallback onChooseFromLibrary;

  /// Null when there is no picked photo to reframe.
  final VoidCallback? onRecrop;

  /// Null when nothing was chosen in this session.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recrop = onRecrop;
    final clear = onClear;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: NoWaveSpacing.xs,
        children: [
          TextButton.icon(
            key: const Key('editor-cover-pick'),
            onPressed: onPick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              hasCover ? l10n.editorCoverReplace : l10n.editorCoverPick,
            ),
          ),
          TextButton.icon(
            key: const Key('editor-cover-library'),
            onPressed: onChooseFromLibrary,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(l10n.editorCoverChooseFromLibrary),
          ),
          if (recrop != null)
            TextButton.icon(
              key: const Key('editor-cover-recrop'),
              onPressed: recrop,
              icon: const Icon(Icons.crop),
              label: Text(l10n.editorCoverRecrop),
            ),
          if (clear != null)
            TextButton.icon(
              key: const Key('editor-cover-clear'),
              onPressed: clear,
              icon: const Icon(Icons.undo),
              label: Text(
                hasPublishedCover
                    ? l10n.editorCoverRestore
                    : l10n.editorCoverRemove,
              ),
            ),
        ],
      ),
    );
  }
}
