import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/features/blog/presentation/widgets/draft_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    required bool isOlderThanPublished,
    required ValueChanged<DraftRecoveryChoice?> onChoice,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,

        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                onChoice(
                  await showDraftRecoveryDialog(
                    context,
                    isOlderThanPublished: isOlderThanPublished,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  for (final entry in {
    '恢复草稿': DraftRecoveryChoice.restore,
    '丢弃草稿': DraftRecoveryChoice.discard,
    '继续当前内容': DraftRecoveryChoice.keepCurrent,
  }.entries) {
    testWidgets('${entry.key} returns the selected action', (tester) async {
      DraftRecoveryChoice? result;
      await openDialog(
        tester,
        isOlderThanPublished: false,
        onChoice: (choice) => result = choice,
      );
      expect(find.textContaining('替换当前编辑内容'), findsOneWidget);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(result, entry.value);
    });
  }

  testWidgets('warns when the published article is newer', (tester) async {
    await openDialog(
      tester,
      isOlderThanPublished: true,
      onChoice: (_) {},
    );
    expect(find.textContaining('比已发布文章旧'), findsOneWidget);
  });

  testWidgets('dismissing the dialog does not select restore', (tester) async {
    DraftRecoveryChoice? result = DraftRecoveryChoice.restore;
    await openDialog(
      tester,
      isOlderThanPublished: false,
      onChoice: (choice) => result = choice,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
