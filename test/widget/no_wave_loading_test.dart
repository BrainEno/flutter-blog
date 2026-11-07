import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
  Locale locale = const Locale('zh'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightThemeMode,
    darkTheme: AppTheme.darkThemeMode,
    themeMode: themeMode,
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: inner!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

/// The decorative rule above the label, found by the token it is sized with.
final _rule = find.byWidgetPredicate(
  (widget) => widget is SizedBox && widget.width == NoWaveSizes.loadingRule,
);

Color _skeletonFill(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(
        of: find.byType(NoWaveSkeletonLine).first,
        matching: find.byType(ColoredBox),
      ),
    )
    .color;

void main() {
  group('NoWaveLoadingLabel', () {
    testWidgets('a loading state is a sentence, not a spinner', (tester) async {
      await tester.pumpWidget(_app(const NoWaveLoadingLabel()));

      expect(find.text('载入中 · LOADING'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'no-wave replaces spinners with words',
      );
    });

    testWidgets('it is announced once, as one sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const NoWaveLoadingLabel()));

      expect(find.bySemanticsLabel('载入中 · LOADING'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a migrated call site keeps the wording it localized', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const NoWaveLoadingLabel(semanticLabel: '正在加载更多文章…')),
      );

      expect(
        find.text('正在加载更多文章…'),
        findsOneWidget,
        reason: 'the visible label defaults to the semantic one',
      );
    });

    testWidgets('a footer drops the rule', (tester) async {
      await tester.pumpWidget(_app(const NoWaveLoadingLabel()));
      expect(_rule, findsOneWidget);

      await tester.pumpWidget(_app(const NoWaveLoadingLabel(compact: true)));
      expect(
        _rule,
        findsNothing,
        reason: 'a list footer is a footnote, not a state',
      );
    });

    testWidgets('the label follows the catalog language', (tester) async {
      await tester.pumpWidget(
        _app(const NoWaveLoadingLabel(), locale: const Locale('en')),
      );

      expect(find.text('LOADING'), findsOneWidget);
    });

    testWidgets('320dp at a doubled text scale does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(const NoWaveLoadingLabel(), textScale: 2));

      expect(tester.takeException(), isNull);
    });

    testWidgets('it holds still', (tester) async {
      await tester.pumpWidget(_app(const NoWaveLoadingLabel()));
      await tester.pumpAndSettle();

      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'a loading label does not animate; motion policy is phase 3',
      );
    });
  });

  group('NoWaveSkeleton', () {
    testWidgets('rows are the shape of the list, announced once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const NoWaveSkeletonList(rows: 3)));

      expect(find.bySemanticsLabel('正在加载…'), findsOneWidget);
      expect(find.byType(NoWaveSkeletonLine), findsNWidgets(9));
      expect(find.byType(NoWaveSkeletonBlock), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      handle.dispose();
    });

    testWidgets('without thumbnails it is text only', (tester) async {
      await tester.pumpWidget(
        _app(const NoWaveSkeletonList(rows: 2, thumbnails: false)),
      );

      expect(find.byType(NoWaveSkeletonBlock), findsNothing);
      expect(find.byType(NoWaveSkeletonLine), findsNWidgets(6));
    });

    testWidgets('the fill is the surface foreground on paper and ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const NoWaveSkeletonLine(), themeMode: ThemeMode.light),
      );
      await tester.pumpAndSettle();
      expect(
        _skeletonFill(tester),
        AppTheme.lightThemeMode.colorScheme.onSurface.withAlpha(
          NoWaveOpacity.skeletonAlpha,
        ),
      );

      await tester.pumpWidget(
        _app(const NoWaveSkeletonLine(), themeMode: ThemeMode.dark),
      );
      // MaterialApp cross-fades between themes; sample after it settles.
      await tester.pumpAndSettle();
      expect(
        _skeletonFill(tester),
        AppTheme.darkThemeMode.colorScheme.onSurface.withAlpha(
          NoWaveOpacity.skeletonAlpha,
        ),
      );
    });

    testWidgets('it does not shimmer', (tester) async {
      await tester.pumpWidget(_app(const NoWaveSkeletonList()));
      await tester.pumpAndSettle();

      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'a static block also reads correctly in a screenshot',
      );
    });

    testWidgets('320dp at a doubled text scale does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(const NoWaveSkeletonList(rows: 3), textScale: 2),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
