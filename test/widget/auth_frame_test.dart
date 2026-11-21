import 'package:belog/core/common/widgets/no_wave_masthead.dart';
import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_frame.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {Size size = const Size(400, 800)}) => MaterialApp(
  theme: AppTheme.lightThemeMode,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: home,
  ),
);

void main() {
  testWidgets('an account page opens like every tab: masthead, then heading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        AuthFrame(
          title: '登录',
          companion: 'Sign in',
          eyebrow: '收藏、评论和写作，从这里开始',
          child: AuthLink(
            prompt: '没有账号？',
            label: '注册',
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    expect(find.byType(NoWaveMasthead), findsOneWidget);
    final heading = tester.widget<NoWaveSectionHeading>(
      find.byType(NoWaveSectionHeading),
    );
    expect(heading.title, '登录');
    expect(heading.companion, 'Sign in');
    // One left edge: heading and link start on the page gutter.
    expect(
      tester.getTopLeft(find.byType(NoWaveSectionHeading)).dx,
      NoWaveSpacing.page,
    );
    expect(tester.getTopLeft(find.byType(TextButton)).dx, NoWaveSpacing.page);
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(NoWaveSizes.tapTarget),
    );

    await tester.tap(find.text('没有账号？注册'));
    expect(taps, 1);
  });

  testWidgets('on a wide screen the form keeps to its measure, centred', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        const AuthFrame(title: '登录', child: SizedBox(height: 10)),
        size: const Size(1000, 800),
      ),
    );

    final heading = tester.getRect(find.byType(NoWaveSectionHeading));
    expect(heading.width, NoWaveSizes.formMeasure);
    expect(heading.center.dx, closeTo(500, 0.5));
  });

  testWidgets('a field is an ink underline that turns orange on focus', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: AuthField(hintText: '邮箱', controller: controller),
        ),
      ),
    );

    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    expect(decoration.filled, isFalse);
    expect(decoration.prefixIcon, isNull);
    final enabled = decoration.enabledBorder! as UnderlineInputBorder;
    expect(enabled.borderSide.width, NoWaveStroke.hairline);
    expect(
      enabled.borderSide.color,
      AppTheme.lightThemeMode.colorScheme.onSurface,
    );
    final focused = decoration.focusedBorder! as UnderlineInputBorder;
    expect(focused.borderSide.width, NoWaveStroke.focus);
    expect(focused.borderSide.color, AppPalette.orange);
    expect(find.text('邮箱'), findsOneWidget);
  });
}
