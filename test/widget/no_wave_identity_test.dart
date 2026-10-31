import 'package:belog/core/common/widgets/no_wave_action_row.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Inspect the builders without mounting an external network image in a test.
class InspectableAvatar extends NoWaveAvatar {
  const InspectableAvatar({required super.name, required super.imageUrl});

  Widget inspect(BuildContext context) => super.build(context);
}

Widget identityApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightThemeMode,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('missing or invalid portraits use a localized neutral fallback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final url in [
        '',
        'file:///tmp/avatar.png',
        'https://',
        'not a URL',
      ]) {
        await tester.pumpWidget(
          identityApp(
            Center(
              child: NoWaveAvatar(name: '小林', imageUrl: url),
            ),
            locale: const Locale('zh'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.byIcon(Icons.person_outline), findsOneWidget);
        expect(find.bySemanticsLabel('小林的头像'), findsOneWidget);
        expect(tester.getSize(find.byType(NoWaveAvatar)), const Size(80, 80));
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a real HTTP image keeps its URL and neutral failure builders', (
    tester,
  ) async {
    const url = 'https://example.org/avatar.webp?version=2';
    late CachedNetworkImage networkImage;
    late BuildContext avatarContext;
    await tester.pumpWidget(
      identityApp(
        Builder(
          builder: (context) {
            avatarContext = context;
            final portrait =
                const InspectableAvatar(
                      name: 'A writer',
                      imageUrl: url,
                    ).inspect(context)
                    as Semantics;
            final excluded = portrait.child! as ExcludeSemantics;
            final square = excluded.child! as SizedBox;
            final background = square.child! as ColoredBox;
            final clip = background.child! as ClipRect;
            networkImage = clip.child! as CachedNetworkImage;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(networkImage.imageUrl, url);
    final loading = networkImage.placeholder!(avatarContext, url) as Center;
    final error =
        networkImage.errorWidget!(avatarContext, url, StateError('offline'))
            as Center;
    expect((loading.child! as Icon).icon, Icons.person_outline);
    expect((error.child! as Icon).icon, Icons.person_outline);
  });

  testWidgets(
    'the action row delegates pointer and keyboard without a router',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        var actions = 0;
        await tester.pumpWidget(
          identityApp(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: NoWaveActionRow(
                label: 'Export my data',
                description:
                    'Export your profile and all your articles as a JSON file',
                icon: Icons.file_download_outlined,
                onTap: () => actions++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp('Export my data')), findsWidgets);
        await tester.tap(find.text('Export my data'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(actions, 2);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
