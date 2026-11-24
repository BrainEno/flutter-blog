import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:belog/core/common/media/cover_crop.dart';
import 'package:belog/core/design/components/no_wave_busy_mark.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/features/blog/presentation/editor/cover_crop_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 transparent PNG: the frame paints a real image without decoding a
/// photo. The fake cropper reports whatever size a test needs.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUA'
  'Aen63NgAAAAASUVORK5CYII=',
);

final _cut = Uint8List.fromList([7, 7, 7]);

class _FakeCropper extends CoverCropper {
  _FakeCropper({this.width = 2000, this.height = 2000, this.readable = true});

  final int width;
  final int height;
  final bool readable;
  Completer<void>? gate;
  CoverCropRequest? request;

  @override
  Future<CoverSource?> prepare(Uint8List bytes) async {
    await gate?.future;
    if (!readable) return null;
    return CoverSource(bytes: bytes, width: width, height: height);
  }

  @override
  Future<Uint8List?> crop(CoverCropRequest request) async {
    this.request = request;
    return _cut;
  }
}

class _Host {
  CoverCropOutcome? outcome;
  bool closed = false;
}

Future<_Host> _open(
  WidgetTester tester,
  _FakeCropper cropper, {
  Rect? initialRect,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool settle = true,
}) async {
  final host = _Host();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              host.outcome = await Navigator.of(context).push(
                coverCropRoute(
                  source: _pngBytes,
                  initialRect: initialRect,
                  cropper: cropper,
                ),
              );
              host.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return host;
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 1e-6));
  expect(actual.top, closeTo(expected.top, 1e-6));
  expect(actual.width, closeTo(expected.width, 1e-6));
  expect(actual.height, closeTo(expected.height, 1e-6));
}

void main() {
  testWidgets('the frame opens centred and Use answers the cut', (
    tester,
  ) async {
    final cropper = _FakeCropper(width: 3200, height: 1000);
    final host = await _open(tester, cropper);

    expect(find.text('Crop cover'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const Key('cover-crop-guides')), findsOneWidget);
    final frame = tester.widget<AspectRatio>(
      find.ancestor(
        of: find.byType(InteractiveViewer),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(frame.aspectRatio, NoWaveSizes.coverAspectWide);

    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    final request = cropper.request!;
    expect(request.aspectRatio, NoWaveSizes.coverAspectWide);
    expect(identical(request.source, _pngBytes), isTrue);
    // A 3.2:1 photo in a 1.6:1 frame keeps its middle half.
    _expectRect(request.rect, const Rect.fromLTWH(0.25, 0, 0.5, 1));
    expect(host.closed, isTrue);
    expect(host.outcome!.isUnsupported, isFalse);
    expect(host.outcome!.bytes, _cut);
    expect(host.outcome!.rect, request.rect);
  });

  testWidgets('reopening starts where the last cut left the frame', (
    tester,
  ) async {
    final cropper = _FakeCropper();
    const previous = Rect.fromLTWH(0.1, 0.2, 0.5, 0.3125);
    await _open(tester, cropper, initialRect: previous);

    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    _expectRect(cropper.request!.rect, previous);
  });

  testWidgets('dragging the photo moves the kept region', (tester) async {
    final cropper = _FakeCropper();
    await _open(tester, cropper);
    final centred = centredCoverRect(
      const Size(2000, 2000),
      NoWaveSizes.coverAspectWide,
    );

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, -60));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cover-crop-use')));
    await tester.pumpAndSettle();

    final rect = cropper.request!.rect;
    expect(rect.top, greaterThan(centred.top));
    expect(rect.width, closeTo(centred.width, 1e-6));
    expect(rect.bottom, lessThanOrEqualTo(1 + 1e-9));
  });

  testWidgets('backing out answers nothing', (tester) async {
    final cropper = _FakeCropper();
    final host = await _open(tester, cropper);

    await tester.tap(find.byKey(const Key('cover-crop-cancel')));
    await tester.pumpAndSettle();

    expect(host.closed, isTrue);
    expect(host.outcome, isNull);
    expect(cropper.request, isNull);
  });

  testWidgets('a photo the codec cannot read closes as unsupported', (
    tester,
  ) async {
    final host = await _open(tester, _FakeCropper(readable: false));

    expect(host.closed, isTrue);
    expect(host.outcome!.isUnsupported, isTrue);
    expect(host.outcome!.rect, isNull);
    expect(find.byType(CoverCropPage), findsNothing);
  });

  testWidgets('Use waits until the photo is ready', (tester) async {
    final cropper = _FakeCropper()..gate = Completer<void>();
    await _open(tester, cropper, settle: false);

    expect(find.byType(NoWaveBusyMark), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
    final use = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('cover-crop-use')),
    );
    expect(use.onPressed, isNull);

    cropper.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('the page fits 320 px at twice the text size', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _open(
      tester,
      _FakeCropper(width: 1000, height: 3000),
      locale: const Locale('zh'),
      textScale: 2,
    );

    expect(find.byKey(const Key('cover-crop-hint')), findsOneWidget);
    expect(find.byKey(const Key('cover-crop-use')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('frame arithmetic', () {
    test('the photo just covers the frame at zoom 1', () {
      expect(
        coverChildSize(const Size(1000, 1000), const Size(320, 200)),
        const Size(320, 320),
      );
      expect(
        coverChildSize(const Size(4000, 1000), const Size(320, 200)),
        const Size(800, 200),
      );
    });

    test('a region and its transform round-trip', () {
      const viewport = Size(320, 200);
      const child = Size(320, 320);
      const rect = Rect.fromLTWH(0.2, 0.3, 0.5, 0.3125);
      final transform = coverTransformForRect(rect, viewport, child, 4);
      expect(transform.entry(0, 0), closeTo(2, 1e-9));
      _expectRect(coverRectForTransform(transform, viewport, child), rect);
    });

    test('a region smaller than the zoom allows is held at the limit', () {
      const viewport = Size(320, 200);
      const child = Size(320, 320);
      final transform = coverTransformForRect(
        const Rect.fromLTWH(0, 0, 0.05, 0.03),
        viewport,
        child,
        4,
      );
      expect(transform.entry(0, 0), 4);
    });

    test('grid guides keep the centred 4:3 middle of a 16:10 frame', () {
      const painter = CoverGuidePainter(
        frameAspect: 16 / 10,
        guideAspect: 4 / 3,
      );
      final kept = painter.keptRect(const Size(320, 200));
      expect(kept.height, 200);
      expect(kept.width, closeTo(200 * 4 / 3, 1e-9));
      expect(kept.center.dx, closeTo(160, 1e-9));
      const tall = CoverGuidePainter(frameAspect: 1, guideAspect: 2);
      final band = tall.keptRect(const Size(200, 200));
      expect(band, const Rect.fromLTWH(0, 50, 200, 100));
      expect(painter.shouldRepaint(tall), isTrue);
      expect(
        painter.shouldRepaint(
          const CoverGuidePainter(frameAspect: 16 / 10, guideAspect: 4 / 3),
        ),
        isFalse,
      );
    });
  });
}
