import 'dart:math' as math;
import 'dart:typed_data';

import 'package:belog/core/common/media/cover_crop.dart';
import 'package:belog/core/common/media/no_wave_image_decode_size.dart';
import 'package:belog/core/design/components/no_wave_busy_mark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// What the crop page answers. A null route result means the author backed
/// out and the previous cover stays.
@immutable
class CoverCropOutcome {
  const CoverCropOutcome.cropped({
    required Uint8List this.bytes,
    required Rect this.rect,
  });

  /// The codec could not read the photo, so nothing was cut.
  const CoverCropOutcome.unsupported() : bytes = null, rect = null;

  /// The cut cover, a JPEG of [CoverCropPage.aspectRatio].
  final Uint8List? bytes;

  /// The kept region in 0..1 coordinates of the upright photo, so a later
  /// "adjust crop" opens where the author left the frame.
  final Rect? rect;

  bool get isUnsupported => bytes == null;
}

/// A route showing [CoverCropPage]; the caller pushes it and keeps the route
/// so it can take it down when the account changes underneath.
MaterialPageRoute<CoverCropOutcome> coverCropRoute({
  required Uint8List source,
  Rect? initialRect,
  CoverCropper cropper = const CoverCropper(),
}) => MaterialPageRoute<CoverCropOutcome>(
  fullscreenDialog: true,
  builder: (_) =>
      CoverCropPage(source: source, initialRect: initialRect, cropper: cropper),
);

/// Frames a picked photo for the cover before it is uploaded.
///
/// The frame has the reader's cover shape ([NoWaveSizes.coverAspectWide]: the
/// feed's lead card and the article header), and the photo moves and zooms
/// under it, always covering it. Grid cards show a narrower middle
/// ([NoWaveSizes.coverAspect]); the bands outside it are shaded so the author
/// sees what a card keeps without a second step.
class CoverCropPage extends StatefulWidget {
  const CoverCropPage({
    super.key,
    required this.source,
    this.initialRect,
    this.cropper = const CoverCropper(),
  });

  /// The cover frame: what the reader header and the lead card show.
  static const aspectRatio = NoWaveSizes.coverAspectWide;

  /// The shape grid cards cut from the same cover.
  static const gridAspectRatio = NoWaveSizes.coverAspect;

  /// How far the photo may be enlarged beyond just covering the frame.
  static const maxZoom = 4.0;

  final Uint8List source;
  final Rect? initialRect;
  final CoverCropper cropper;

  @override
  State<CoverCropPage> createState() => _CoverCropPageState();
}

class _CoverCropPageState extends State<CoverCropPage> {
  CoverSource? _source;
  Rect? _rect;
  Size? _viewport;
  Size? _child;
  TransformationController? _controller;
  bool _cropping = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final prepared = await _safePrepare();
    if (!mounted) return;
    if (prepared == null) {
      _close(const CoverCropOutcome.unsupported());
      return;
    }
    setState(() {
      _source = prepared;
      _rect =
          widget.initialRect ??
          centredCoverRect(prepared.size, CoverCropPage.aspectRatio);
    });
  }

  Future<CoverSource?> _safePrepare() async {
    try {
      return await widget.cropper.prepare(widget.source);
    } catch (_) {
      return null;
    }
  }

  void _close(CoverCropOutcome? outcome) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(outcome);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The region under the frame right now.
  Rect? _currentRect() {
    final controller = _controller;
    final viewport = _viewport;
    final child = _child;
    if (controller == null || viewport == null || child == null) return _rect;
    return coverRectForTransform(controller.value, viewport, child);
  }

  Future<void> _use() async {
    final source = _source;
    final rect = _currentRect();
    if (source == null || rect == null || _cropping) return;
    setState(() => _cropping = true);
    final cut = await _safeCrop(
      CoverCropRequest(
        source: source.bytes,
        rect: rect,
        aspectRatio: CoverCropPage.aspectRatio,
      ),
    );
    if (!mounted) return;
    _close(
      cut == null
          ? const CoverCropOutcome.unsupported()
          : CoverCropOutcome.cropped(bytes: cut, rect: rect),
    );
  }

  Future<Uint8List?> _safeCrop(CoverCropRequest request) async {
    try {
      return await widget.cropper.crop(request);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ready = _source != null && !_cropping;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.coverCropTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(NoWaveSpacing.medium),
                  child: AspectRatio(
                    aspectRatio: CoverCropPage.aspectRatio,
                    child: _source == null
                        ? Center(
                            child: NoWaveBusyMark(
                              semanticsLabel: l10n.coverCropPreparing,
                            ),
                          )
                        : LayoutBuilder(builder: _frame),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NoWaveSpacing.medium,
              ),
              child: Text(
                l10n.coverCropHint,
                key: const Key('cover-crop-hint'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NoWaveSpacing.medium),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: NoWaveSpacing.small,
                overflowSpacing: NoWaveSpacing.small,
                children: [
                  TextButton(
                    key: const Key('cover-crop-cancel'),
                    onPressed: _cropping ? null : () => _close(null),
                    child: Text(l10n.actionCancel),
                  ),
                  FilledButton.icon(
                    key: const Key('cover-crop-use'),
                    onPressed: ready ? () => _use() : null,
                    icon: _cropping
                        ? const NoWaveBusyMark()
                        : const Icon(Icons.crop),
                    label: Text(l10n.coverCropUse),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, BoxConstraints constraints) {
    final source = _source!;
    final viewport = constraints.biggest;
    final child = coverChildSize(source.size, viewport);
    if (_viewport != viewport || _controller == null) {
      // A new frame size (first layout, rotation, a split screen) keeps the
      // region the author chose, not the old pixel offsets. Building a fresh
      // controller instead of assigning one avoids notifying a listener while
      // this frame is being built.
      final previous = _controller;
      final rect = _currentRect() ?? _rect!;
      _rect = rect;
      _viewport = viewport;
      _child = child;
      _controller = TransformationController(
        coverTransformForRect(rect, viewport, child, CoverCropPage.maxZoom),
      );
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }
    final decodeWidth = math.min(
      source.width,
      NoWaveImageDecodeSize.maxDimension,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(NoWaveRadius.container),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            key: ValueKey(viewport),
            transformationController: _controller,
            constrained: false,
            boundaryMargin: EdgeInsets.zero,
            minScale: 1,
            maxScale: CoverCropPage.maxZoom,
            onInteractionEnd: (_) => _rect = _currentRect(),
            child: SizedBox.fromSize(
              size: child,
              child: Semantics(
                image: true,
                label: context.l10n.coverImage,
                child: Image.memory(
                  source.bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  cacheWidth: decodeWidth,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              key: const Key('cover-crop-guides'),
              painter: CoverGuidePainter(
                frameAspect: CoverCropPage.aspectRatio,
                guideAspect: CoverCropPage.gridAspectRatio,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo's size at zoom 1: just large enough to cover [viewport].
Size coverChildSize(Size source, Size viewport) {
  final scale = math.max(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  return Size(source.width * scale, source.height * scale);
}

/// The 0..1 region of the photo under the frame for a viewer [transform]
/// (a zoom and a pan, no rotation) of a [child]-sized photo in [viewport].
Rect coverRectForTransform(Matrix4 transform, Size viewport, Size child) {
  final scale = transform.entry(0, 0);
  final dx = transform.entry(0, 3);
  final dy = transform.entry(1, 3);
  return clampCoverRect(
    Rect.fromLTWH(
      -dx / scale / child.width,
      -dy / scale / child.height,
      viewport.width / scale / child.width,
      viewport.height / scale / child.height,
    ),
  );
}

/// The viewer transform that puts [rect] of a [child]-sized photo under the
/// frame: the inverse of [coverRectForTransform], zoom kept in 1..[maxZoom].
Matrix4 coverTransformForRect(
  Rect rect,
  Size viewport,
  Size child,
  double maxZoom,
) {
  final clamped = clampCoverRect(rect);
  final scale = clamped.width <= 0
      ? 1.0
      : (viewport.width / (clamped.width * child.width))
            .clamp(1.0, maxZoom)
            .toDouble();
  final maxDx = child.width * scale - viewport.width;
  final maxDy = child.height * scale - viewport.height;
  final dx = (clamped.left * child.width * scale)
      .clamp(0.0, math.max(0.0, maxDx))
      .toDouble();
  final dy = (clamped.top * child.height * scale)
      .clamp(0.0, math.max(0.0, maxDy))
      .toDouble();
  return Matrix4.diagonal3Values(scale, scale, 1)
    ..setTranslationRaw(-dx, -dy, 0);
}

/// Shades the parts of the frame a grid card leaves out and outlines the
/// part it keeps.
class CoverGuidePainter extends CustomPainter {
  const CoverGuidePainter({
    required this.frameAspect,
    required this.guideAspect,
  });

  final double frameAspect;
  final double guideAspect;

  /// The rectangle a grid card keeps, centred in a frame of [size].
  Rect keptRect(Size size) {
    if (guideAspect < frameAspect) {
      final width = size.height * guideAspect;
      return Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
    }
    final height = size.width / guideAspect;
    return Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    final kept = keptRect(size);
    final shade = Paint()
      ..color = AppPalette.ink.withAlpha((0.35 * 255).toInt());
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(frame),
        Path()..addRect(kept),
      ),
      shade,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = NoWaveStroke.hairline
      ..color = AppPalette.paper.withAlpha((0.85 * 255).toInt());
    canvas.drawRect(kept.deflate(NoWaveStroke.hairline / 2), line);
  }

  @override
  bool shouldRepaint(CoverGuidePainter oldDelegate) =>
      oldDelegate.frameAspect != frameAspect ||
      oldDelegate.guideAspect != guideAspect;
}
