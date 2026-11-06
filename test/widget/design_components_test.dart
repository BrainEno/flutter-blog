import 'package:belog/core/design/components/no_wave_badge.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget testApp(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
}) => MaterialApp(
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

/// The resolved label of a button's own `TextButton` style.
ButtonStyle? textButtonStyle(WidgetTester tester) =>
    tester.widget<TextButton>(find.byType(TextButton)).style;

void main() {
  group('NoWaveButton', () {
    for (final variant in NoWaveButtonVariant.values) {
      testWidgets('$variant renders its label and takes the tap', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(
          testApp(
            NoWaveButton(
              label: '继续',
              variant: variant,
              onPressed: () => taps++,
            ),
          ),
        );

        expect(find.text('继续'), findsOneWidget);
        await tester.tap(find.byType(NoWaveButton));
        expect(taps, 1);
      });
    }

    testWidgets('a disabled button keeps its target size and ignores taps', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const NoWaveButton(label: '保存', onPressed: null)),
      );

      expect(
        tester.getSize(find.byType(NoWaveButton)).height,
        greaterThanOrEqualTo(NoWaveSizes.tapTarget),
      );
      await tester.tap(find.byType(NoWaveButton));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a busy button keeps its label and reports unavailable', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      var taps = 0;
      await tester.pumpWidget(
        testApp(
          NoWaveButton(label: '发布', isLoading: true, onPressed: () => taps++),
        ),
      );

      // The label stays in the layout so the button does not resize.
      expect(find.text('发布'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(NoWaveButton));
      await tester.pump();
      expect(taps, 0);

      // The button is no longer pressable and the label is still announced.
      final textButton = tester.widget<TextButton>(find.byType(TextButton));
      expect(textButton.onPressed, isNull);
      expect(tester.getSemantics(find.text('发布')).label, contains('发布'));
    });

    testWidgets('the destructive variant uses the error colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          NoWaveButton(
            label: '删除',
            variant: NoWaveButtonVariant.destructive,
            onPressed: () {},
          ),
        ),
      );

      expect(
        textButtonStyle(tester)?.foregroundColor?.resolve({}),
        AppTheme.lightThemeMode.colorScheme.error,
      );
    });

    testWidgets('the primary variant is filled and full-height', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(NoWaveButton(label: '发布', onPressed: () {})),
      );

      expect(
        textButtonStyle(tester)?.backgroundColor?.resolve({}),
        AppTheme.lightThemeMode.colorScheme.primary,
      );
      expect(
        tester.getSize(find.byType(NoWaveButton)).height,
        greaterThanOrEqualTo(NoWaveSizes.primaryAction),
      );
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('buttons still fit at 2x text: $mode', (tester) async {
        await tester.pumpWidget(
          testApp(
            SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NoWaveButton(
                    label: '保存并发布这篇文章',
                    icon: Icons.send,
                    expand: true,
                    onPressed: () {},
                  ),
                  NoWaveButton(
                    label: '取消',
                    variant: NoWaveButtonVariant.quiet,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            themeMode: mode,
            textScale: 2,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a semantic label replaces the ambiguous visible text', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await tester.pumpWidget(
        testApp(
          NoWaveButton(
            label: '删除',
            semanticLabel: '删除《城与季节》',
            variant: NoWaveButtonVariant.destructive,
            onPressed: () {},
          ),
        ),
      );

      // The visible text is unchanged; only the announced label differs.
      expect(find.text('删除'), findsOneWidget);
      expect(tester.getSemantics(find.byType(NoWaveButton)).label, '删除《城与季节》');
    });
  });

  group('NoWaveBadge', () {
    testWidgets('keeps one line and does not overflow a narrow tile', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const SizedBox(
            width: 90,
            child: NoWaveBadge(label: 'Chinese (Traditional) 繁體中文版本'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(
        find.text('Chinese (Traditional) 繁體中文版本'),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the two tones use different surfaces', (tester) async {
      await tester.pumpWidget(
        testApp(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoWaveBadge(label: '草稿'),
              NoWaveBadge(label: 'English', tone: NoWaveBadgeTone.neutral),
            ],
          ),
        ),
      );

      BoxDecoration decorationOf(int index) {
        final box = find
            .descendant(
              of: find.byType(NoWaveBadge).at(index),
              matching: find.byType(DecoratedBox),
            )
            .first;
        return tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
      }

      expect(decorationOf(0).color, isNot(decorationOf(1).color));
    });
  });

  group('NoWaveNotice', () {
    testWidgets('an error notice offers the retry next to its message', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        testApp(
          NoWaveNotice(
            message: '连接失败，请重试',
            tone: NoWaveNoticeTone.error,
            actionLabel: '重试',
            onAction: () => retried++,
          ),
        ),
      );

      expect(find.text('连接失败，请重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a static note does not interrupt the reader', (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await tester.pumpWidget(
        testApp(const NoWaveNotice(message: '草稿只有你自己能看到。')),
      );

      final node = tester.getSemantics(find.byType(NoWaveNotice));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isFalse);
      expect(data.label, contains('草稿只有你自己能看到。'));
    });

    testWidgets('a live notice announces itself', (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await tester.pumpWidget(
        testApp(const NoWaveNotice(message: '已保存', isLive: true)),
      );

      final node = tester.getSemantics(find.byType(NoWaveNotice));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('an action needs both a label and a handler', (tester) async {
      expect(
        () => NoWaveNotice(message: 'x', actionLabel: '重试'),
        throwsAssertionError,
      );
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the note fits 2x text in a narrow column: $mode', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            const SizedBox(
              width: 240,
              child: NoWaveNotice(
                message: '这套部署只能列出当前语言的文章，看不到其他语言版本。',
                tone: NoWaveNoticeTone.warning,
              ),
            ),
            themeMode: mode,
            textScale: 2,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('showNoWaveConfirmDialog', () {
    /// Opens the dialog and hands back the future it will complete.
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> pending;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => NoWaveButton(
              label: '删除',
              variant: NoWaveButtonVariant.destructive,
              onPressed: () {
                pending = showNoWaveConfirmDialog(
                  context,
                  title: '删除文章',
                  message: '确定删除这篇文章吗？',
                  cancelLabel: '取消',
                  confirmLabel: '删除',
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(NoWaveButton));
      await tester.pumpAndSettle();
      return pending;
    }

    testWidgets('confirming completes with true', (tester) async {
      final pending = await open(tester);
      expect(find.text('确定删除这篇文章吗？'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();

      expect(await pending, isTrue);
    });

    testWidgets('cancelling completes with false', (tester) async {
      final pending = await open(tester);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(await pending, isFalse);
    });

    testWidgets('dismissing without a choice is false, never undecided', (
      tester,
    ) async {
      final pending = await open(tester);

      // Closing the dialog is not consent.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(await pending, isFalse);
    });

    testWidgets('the confirm action is styled destructive', (tester) async {
      await open(tester);

      final confirm = tester.widget<NoWaveButton>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('删除'),
          ),
          matching: find.byType(NoWaveButton),
        ),
      );
      expect(confirm.variant, NoWaveButtonVariant.destructive);
    });

    testWidgets('a non-destructive confirm is not painted as an error', (
      tester,
    ) async {
      late Future<bool> pending;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => NoWaveButton(
              label: '打开',
              onPressed: () {
                pending = showNoWaveConfirmDialog(
                  context,
                  title: '保存草稿',
                  message: '保存后可以继续编辑。',
                  cancelLabel: '取消',
                  confirmLabel: '保存',
                  destructive: false,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(NoWaveButton));
      await tester.pumpAndSettle();

      final confirm = tester.widget<NoWaveButton>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('保存'),
          ),
          matching: find.byType(NoWaveButton),
        ),
      );
      expect(confirm.variant, NoWaveButtonVariant.primary);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await pending, isFalse);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the dialog survives 2x text on a narrow screen: $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          testApp(
            Builder(
              builder: (context) => NoWaveButton(
                label: '打开',
                onPressed: () => showNoWaveConfirmDialog(
                  context,
                  title: '结束其他会话',
                  message: '除了当前设备，其他已登录的会话都会退出登录。',
                  cancelLabel: '取消',
                  confirmLabel: '全部结束',
                ),
              ),
            ),
            themeMode: mode,
            textScale: 2,
          ),
        );
        await tester.tap(find.byType(NoWaveButton));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
