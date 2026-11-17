import 'package:belog/features/blog/presentation/editor/editor_cover_field.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cover placeholder keeps its rounded dashed border options', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: EditorCoverField(onTap: () {})),
      ),
    );

    final border = tester.widget<DottedBorder>(find.byType(DottedBorder));
    expect(border.options, isA<RoundedRectDottedBorderOptions>());
    final options = border.options as RoundedRectDottedBorderOptions;
    expect(options.radius, const Radius.circular(12));
    expect(options.dashPattern, const [6.0, 3.0]);
    expect(options.strokeCap, StrokeCap.round);
  });
}
