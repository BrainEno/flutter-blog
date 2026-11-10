import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/blog/presentation/widgets/blog_feed_skeleton.dart';
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
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('it is shaped like the feed: one cover and compact rows', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const BlogFeedSkeleton()));

    expect(find.byType(NoWaveSkeletonBlock), findsOneWidget);
    expect(find.byType(NoWaveSkeletonDivider), findsNWidgets(4));
    // Four lines on the featured card (meta, two title lines, author) and
    // three on each of the four rows.
    expect(find.byType(NoWaveSkeletonLine), findsNWidgets(16));
    expect(find.byType(NoWaveSkeleton), findsOneWidget);
  });

  testWidgets('a compact list has rows but no featured cover', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);
    await tester.pumpWidget(
      _app(
        const BlogFeedSkeleton(
          showFeatured: false,
          rows: 3,
          semanticLabel: 'Loading articles',
        ),
      ),
    );

    expect(find.byType(NoWaveSkeletonBlock), findsNothing);
    expect(find.byType(NoWaveSkeletonDivider), findsNWidgets(3));
    expect(find.byType(NoWaveSkeletonLine), findsNWidgets(9));
    expect(find.bySemanticsLabel('Loading articles'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the cover keeps the ratio the real cover uses', (tester) async {
    await tester.pumpWidget(_app(const BlogFeedSkeleton()));

    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
    expect(ratio.aspectRatio, NoWaveSizes.coverAspectWide);
  });

  testWidgets('the row count is the caller’s', (tester) async {
    await tester.pumpWidget(_app(const BlogFeedSkeleton(rows: 2)));

    expect(find.byType(NoWaveSkeletonDivider), findsNWidgets(2));
    expect(find.byType(NoWaveSkeletonLine), findsNWidgets(10));
  });

  testWidgets('it is announced once and never spins', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _app(const BlogFeedSkeleton(semanticLabel: '正在加载文章…')),
      );

      expect(find.bySemanticsLabel('正在加载文章…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('it holds still', (tester) async {
    await tester.pumpWidget(_app(const BlogFeedSkeleton()));
    await tester.pumpAndSettle();

    // A skeleton that shimmers keeps the frame pipeline awake; a static one
    // leaves nothing scheduled.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('it fits a narrow screen at double text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const BlogFeedSkeleton(), textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
