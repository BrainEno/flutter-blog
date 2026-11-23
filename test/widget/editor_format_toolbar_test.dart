import 'dart:async';

import 'package:belog/features/blog/presentation/editor/editor_format_toolbar.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focus;
  late UndoHistoryController undo;

  setUp(() {
    controller = TextEditingController();
    focus = FocusNode();
    undo = UndoHistoryController();
  });

  tearDown(() {
    controller.dispose();
    focus.dispose();
    undo.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<String?> Function()? onPickImage,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                controller: controller,
                focusNode: focus,
                undoController: undo,
                maxLines: null,
              ),
              const Spacer(),
              EditorFormatToolbar(
                controller: controller,
                focusNode: focus,
                undoController: undo,
                onPickImage: onPickImage,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void select(String text, int start, [int? end]) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
    );
  }

  Future<void> tapTool(WidgetTester tester, String id) async {
    final tool = find.byKey(Key('editor-tool-$id'));
    await tester.ensureVisible(tool);
    await tester.pump();
    await tester.tap(tool);
    await tester.pump();
  }

  testWidgets('inline and line tools rewrite the Markdown in place', (
    tester,
  ) async {
    await pump(tester);
    select('make it loud', 8, 12);
    await tapTool(tester, 'bold');
    expect(controller.text, 'make it **loud**');

    select('Title', 5);
    await tapTool(tester, 'heading');
    expect(controller.text, '## Title');

    select('milk', 0, 4);
    await tapTool(tester, 'bullet');
    expect(controller.text, '- milk');

    select('words', 0, 5);
    await tapTool(tester, 'quote');
    expect(controller.text, '> words');

    select('x', 0, 1);
    await tapTool(tester, 'code-block');
    expect(controller.text, '```\nx\n```\n');
    // Pressing a tool hands the caret back to the body.
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('undo is offered only once there is something to undo', (
    tester,
  ) async {
    await pump(tester);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('editor-tool-undo')),
    );
    expect(button.onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('editor-tool-redo')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a link needs an address no-wave accepts', (tester) async {
    await pump(tester);
    select('read docs', 5, 9);
    await tapTool(tester, 'link');
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.editorLinkDialogTitle), findsOneWidget);
    // The words are already selected, so only the address is asked for.
    expect(find.byKey(const Key('editor-link-words')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('editor-link-url')),
      'javascript:alert',
    );
    await tester.tap(find.byKey(const Key('editor-link-insert')));
    await tester.pump();
    expect(find.text(l10n.editorLinkInvalid), findsOneWidget);
    expect(controller.text, 'read docs');

    await tester.enterText(
      find.byKey(const Key('editor-link-url')),
      'https://example.com/docs',
    );
    await tester.tap(find.byKey(const Key('editor-link-insert')));
    await tester.pumpAndSettle();
    expect(controller.text, 'read [docs](https://example.com/docs)');
  });

  testWidgets('a link at a caret asks for its words too', (tester) async {
    await pump(tester);
    select('', 0);
    await tapTool(tester, 'link');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-link-words')), 'site');
    await tester.enterText(
      find.byKey(const Key('editor-link-url')),
      'https://example.com',
    );
    await tester.tap(find.byKey(const Key('editor-link-insert')));
    await tester.pumpAndSettle();
    expect(controller.text, '[site](https://example.com)');
  });

  testWidgets('an uploaded image lands in the body; a cancel changes nothing', (
    tester,
  ) async {
    var answer = Completer<String?>();
    await pump(tester, onPickImage: () => answer.future);
    select('Intro', 5);

    await tapTool(tester, 'image');
    // While the upload runs the button is a progress mark.
    expect(find.byKey(const Key('editor-tool-image')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    answer.complete('https://example.com/p.png');
    await tester.pump();
    await tester.pump();
    expect(controller.text, 'Intro\n\n![](https://example.com/p.png)\n');
    expect(find.byKey(const Key('editor-tool-image')), findsOneWidget);

    answer = Completer<String?>();
    final before = controller.text;
    await tapTool(tester, 'image');
    answer.complete(null);
    await tester.pump();
    await tester.pump();
    expect(controller.text, before);
  });

  testWidgets('without an uploader there is no image button', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('editor-tool-image')), findsNothing);
  });

  testWidgets('the keyboard button lets go of the body', (tester) async {
    await pump(tester);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('editor-tool-done')));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
