import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/blog/presentation/widgets/blog_grid_skeleton.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {double textScale = 1}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightThemeMode,
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: inner!,
    ),
    home: Scaffold(body: child),
  );
}

/// How many distinct columns the tiles land in.
int _columns(WidgetTester tester) {
  final blocks = find.byType(NoWaveSkeletonBlock);
  final lefts = <double>{
    for (var i = 0; i < blocks.evaluate().length; i++)
      tester.getTopLeft(blocks.at(i)).dx,
  };
  return lefts.length;
}

void main() {
  testWidgets('it draws a tile per placeholder: cover and four lines', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const BlogGridSkeleton()));

    expect(find.byType(NoWaveSkeletonBlock), findsNWidgets(6));
    expect(find.byType(NoWaveSkeletonLine), findsNWidgets(24));
    expect(find.byType(NoWaveSkeleton), findsOneWidget);
  });

  testWidgets('the column count is the real grid’s', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const BlogGridSkeleton(tiles: 8)));
    await tester.pumpAndSettle();

    expect(_columns(tester), NoWaveBreakpoints.columnsFor(900));

    tester.view.physicalSize = const Size(360, 1200);
    await tester.pumpWidget(_app(const BlogGridSkeleton(tiles: 8)));
    await tester.pumpAndSettle();

    expect(_columns(tester), NoWaveBreakpoints.columnsFor(360));
  });

  testWidgets('the cover keeps the tile ratio', (tester) async {
    await tester.pumpWidget(_app(const BlogGridSkeleton()));

    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
    expect(ratio.aspectRatio, NoWaveSizes.coverAspect);
  });

  testWidgets('the tile count is the caller’s', (tester) async {
    await tester.pumpWidget(_app(const BlogGridSkeleton(tiles: 2)));

    expect(find.byType(NoWaveSkeletonBlock), findsNWidgets(2));
    expect(find.byType(NoWaveSkeletonLine), findsNWidgets(8));
  });

  testWidgets('it is announced once and never spins', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _app(const BlogGridSkeleton(semanticLabel: '正在加载文章…')),
      );

      expect(find.bySemanticsLabel('正在加载文章…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('it holds still', (tester) async {
    await tester.pumpWidget(_app(const BlogGridSkeleton()));
    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('it fits a narrow screen at double text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(const BlogGridSkeleton(tiles: 4), textScale: 2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
