import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Inspect the built portrait without mounting an external network image, like
// `no_wave_identity_test.dart` does for the same widget.
class InspectableAvatar extends NoWaveAvatar {
  const InspectableAvatar({
    super.key,
    required super.name,
    required super.imageUrl,
    super.webBaseUrl,
  });

  Widget inspect(BuildContext context) => super.build(context);
}

/// Builds [avatar] inside a localized app and returns the built widget.
Future<Widget> buildAvatar(
  WidgetTester tester,
  InspectableAvatar avatar,
) async {
  late Widget built;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            built = avatar.inspect(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return built;
}

/// The image slot inside the portrait's fixed layout.
Widget portraitOf(Widget built) {
  final semantics = built as Semantics;
  final excluded = semantics.child! as ExcludeSemantics;
  final square = excluded.child! as SizedBox;
  final background = square.child! as ColoredBox;
  return (background.child! as ClipRect).child!;
}

void main() {
  testWidgets('an absolute avatar is loaded as a network image', (
    tester,
  ) async {
    final built = await buildAvatar(
      tester,
      const InspectableAvatar(
        name: '无浪',
        imageUrl: 'https://cdn.test/a.webp',
      ),
    );

    final image = portraitOf(built) as CachedNetworkImage;
    expect(image.imageUrl, 'https://cdn.test/a.webp');
  });

  testWidgets('a site-relative avatar resolves against the web origin', (
    tester,
  ) async {
    // no-wave's validateProfileUrl(allowRelative: true) accepts this shape.
    final built = await buildAvatar(
      tester,
      const InspectableAvatar(
        name: '无浪',
        imageUrl: '/avatars/me.webp',
        webBaseUrl: 'https://site.test',
      ),
    );

    final image = portraitOf(built) as CachedNetworkImage;
    expect(image.imageUrl, 'https://site.test/avatars/me.webp');
  });

  testWidgets('a relative avatar without a web origin stays neutral', (
    tester,
  ) async {
    final built = await buildAvatar(
      tester,
      const InspectableAvatar(name: '无浪', imageUrl: '/avatars/me.webp'),
    );

    final portrait = portraitOf(built) as Center;
    expect((portrait.child! as Icon).icon, Icons.person_outline);
  });

  testWidgets('an untrusted avatar is never loaded, even when configured', (
    tester,
  ) async {
    for (final value in <String>[
      '//evil.test/a.webp',
      'javascript:alert(1)',
      'data:image/png;base64,AAAA',
      'file:///etc/passwd',
      'https://user:pass@evil.test/a.webp',
    ]) {
      final built = await buildAvatar(
        tester,
        InspectableAvatar(
          name: '无浪',
          imageUrl: value,
          webBaseUrl: 'https://site.test',
        ),
      );

      final portrait = portraitOf(built) as Center;
      expect((portrait.child! as Icon).icon, Icons.person_outline);
    }
  });

  testWidgets('the portrait keeps its localized image semantics', (
    tester,
  ) async {
    final built = await buildAvatar(
      tester,
      const InspectableAvatar(name: '无浪', imageUrl: '/avatars/me.webp'),
    );

    final semantics = built as Semantics;
    expect(semantics.properties.label, '无浪的头像');
    expect(semantics.properties.image, isTrue);
  });
}
